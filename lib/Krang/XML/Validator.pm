package Krang::XML::Validator;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use File::Find qw();
use File::Path qw(rmtree);
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Cwd qw(fastcwd);
use File::Spec::Functions qw(catdir catfile splitdir);
use Krang::ClassLoader Conf => qw(KrangRoot);
use XML::SAX::Expat;
use XML::Validator::Schema;
use Carp qw(croak);

=head1 NAME

Krang::XML::Validator - validate XML documents against XML Schemas

=head1 SYNOPSIS

  # create a new validator
  $validator = pkg('XML::Validator')->new();

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

    return $self;
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

    # pull the schema name out of the SchemaLocation directive
    open(XML, $path) or die "Unable to open $path: $!";
    my $xsd;
    while(defined(my $line = <XML>)) {
        next unless $line =~ /noNamespaceSchemaLocation\s*=\s*"(.*?)"/;
        $xsd = $1;
        last;
    }
    close XML or die $!;
    return (0, "$path is missing noNamespaceSchemaLocation attribute necessary for schema validation.")
      unless $xsd;

    # run the file through the schema validator
    my $validator = XML::Validator::Schema->new(file => catfile(KrangRoot, 
                                                                "schema",
                                                                $xsd),
                                                cache => 1,
                                               );

    # explicitely use Expat. It's not worth the risk to use the
    # ParserFactory.
    my $parser = XML::SAX::Expat->new(Handler => $validator);

    eval { $parser->parse_uri($path); };

    # all done, return results
    return (1, undef) unless $@;
    return (0, $@);
}

=back

=cut

1;
