package Krang::XML::Validator;
use strict;
use warnings;

use File::Find qw();
use File::Path qw(rmtree);
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Cwd qw(fastcwd);
use File::Spec::Functions qw(catdir catfile splitdir);
use Krang::Conf qw(KrangRoot);

=head1 NAME

Krang::XML::Validator - validate XML documents against XML Schemas

=head1 SYNOPSIS

  # create a new validator
  $validator = Krang::XML::Validator->new();

  # validate a file
  ($ok, $msg) = $validator->validate(path => 'story1024.xml');

  # deal with results
  unless ($ok) {
    croak "That story just ain't right: $msg";
  }

=head1 DESCRIPTION

This module allows you to validate XML documents against schemas
stored in C<$KRANG_ROOT/schema>.  The documents must contain schema
declarations like this one in their root element:

  <index xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="index.xsd">

The C<.xsd> file specified for C<xsi:noNamespaceSchemaLocation> must
exist in C<$KRANG_ROOT/schema>.

=head1 INTERFACE

=over

=item C<< $validator = Krang::XML::Validator = Krang::XML::Validator->new() >>

Creates a new validator object.  If you'll be validating multiple
files you can save a bit of time by reusing the same validator for all
of them.

=cut

sub new {
    my $pkg = shift;
    my $self = bless({}, $pkg);
    local $_;

    # create a temp directory to hold links to .xsd files
    my $temp_dir = tempdir( DIR => catdir(KrangRoot, 'tmp')); 
    $self->{temp_dir} = $temp_dir;

    # switch into it
    my $old_dir = fastcwd;
    chdir($temp_dir) or die "Unable to chdir to '$temp_dir': $!";
    
    # prepare links to schema documents so schema processing can work
    my @links;
    File::Find::find(sub { 
             return unless /\.xsd$/; 
             my $link = catfile($temp_dir, $_);
             link(catfile(KrangRoot, "schema", $_), $link)
               or die "Unable to link $_ to $link : $!";
         }, catdir(KrangRoot, "schema"));

    # gotta get back
    chdir($old_dir) or die "Can't get back to '$old_dir' : $!";

    return $self;
}

# zap the temp dir with the object
sub DESTROY {
    my $self = shift;
    rmtree($self->{temp_dir}) if $self->{temp_dir};
}

=item C<< ($ok, $msg) = $validator->validate(path => 'foo.xml') >>

Validate a single XML file.  Returns C<< (1, undef) >> if the file
passed, otherwise returns C<< (0, "msg") >> describing the problem.
Will croak if validation cannot be performed.

=cut

sub validate {
    my ($self, %arg) = @_;
    my $path = $arg{path};
    croak("Missing required path parameter") unless $path;
    croak("Specified path '$path' does not exist") unless -e $path;
    my $temp_dir = $self->{temp_dir};
    my $filename = (splitdir($path))[-1];

    # copy the file into the temp dir (maybe link instead?)
    copy($path, catfile($temp_dir, $filename))
      or croak("Unable to copy $path into $temp_dir/$filename: $!");

    # follow it
    my $old_dir = fastcwd;
    chdir($temp_dir) or die "Unable to chdir to '$temp_dir': $!";

    # make sure it has an XML Schema declaration
    open(XML, $filename) or die "Unable to open $filename: $!";
    my $found = 0;
    while(defined(my $line = <XML>)) {
        if ($line =~ /xmlns:xsi.*xsi:noNamespaceSchemaLocation/) {
            $found = 1;
            last;
        }
    }
    close XML or die $!;
    return (0, "$filename is missing xmlns:xsi and xsi:noNamespaceSchemaLocation attributes necessary for schema validation.")
      unless $found;

    # call out to DOMCount for the validation    
    my $DOMCount = catfile(KrangRoot, 'xerces', 'DOMCount');
    local $ENV{LD_LIBRARY_PATH} = catdir(KrangRoot, 'xerces', 'lib') . 
      ($ENV{LD_LIBRARY_PATH} ? ":$ENV{LD_LIBRARY_PATH}" : "");
    my $error = `$DOMCount -n -s -f $filename 2>&1`;

    # gotta get back
    chdir($old_dir) or die "Can't get back to '$old_dir' : $!";

    # success?
    return (1, undef) unless $error =~ /Error/;

    # fixup error message
    $error =~ s{\Q$temp_dir\E/?}{}g;
    $error =~ s!Errors occurred, no output available!!g;
    $error =~ s!^\s+!!;
    $error =~ s{\s+$}{};

    # return the message
    return (0, $error);
}

=back

=head1 TODO

Implement better XML Schema validation than calling out to DOMCount.
Inline::C, XML::Xerces, anything...

=cut

1;
