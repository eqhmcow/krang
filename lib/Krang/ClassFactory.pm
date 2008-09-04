package Krang::ClassFactory;
use strict;
use warnings;

use Krang::lib;
use File::Spec::Functions qw(catdir catfile);
use Config::ApacheFormat;
use Carp qw(croak);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(pkg);


=head1 NAME

Krang::ClassFactory - a registry for class names allowing runtime overrides

=head1 SYNOPSIS

  use Krang::ClassLoader ClassFactory => qw(pkg);

  # instead of this
  pkg('Story')->new(...);

  # write this:
  pkg('Story')->new();

=head1 DESCRIPTION

This module mainatins a table of class names which allows addons to
selectively override core Krang classes.  AddOns declare their
overrides via a F<conf/class.conf> file.  For example, if the
Turbo-1.00.tar.gz addon contains a F<conf/class.conf> file with:

  SetClass Story      Turbo::Story
  SetClass CGI::Story Turbo::CGI::Story

Then Krang will return 'Turbo::Story' for calls to pkg('Story') and
'Turbo::CGI::Story' for pkg('CGI::Story').  This will have the effect
of dynamically substituting Turbo::Story for Krang::Story and
Turbo::CGI::Story for Krang::Story.  The benefit of this over just
including C<lib/Krang/Story.pm> in the addon is that Turbo's classes
can (and probably I<should>) inherit from Krang::Story and
Krang::CGI::Story to implement its functionality.

=head1 INTERFACE

=head2 pkg($class_name)

This function returns a class name (ex. Krang::Story) given a partial
class name (Story).  By default this function meerly appends Krang::
to the name passed in, unless an addon has registered an override, in
which case that will be returned instead.

The name for this function was chosen primarily for its size.  Since
pkg('foo') is exactly as long as Krang:: this new system was added via
search-and-replace without breaking any code formatting.

=cut

our %CLASSES;

sub pkg {
    return "Krang::" . $_[0] unless exists $CLASSES{$_[0]};
    return $CLASSES{$_[0]};
}

sub reload_configuration {
    my $pkg = shift;
    %CLASSES = ();
    $pkg->load_configuration();
}

# load the class.conf files from addons
sub load_configuration {
    my $pkg = shift;

    my $root = $ENV{KRANG_ROOT} 
     or croak("KRANG_ROOT must be defined before loading Krang::ClassFactory");

    # using Krang::Addon would be easier but this module shouldn't
    # load any Krang:: modules since that will prevent them from being
    # overridden in addons via class.conf
    opendir(my $dir, catdir($root, 'addons'));
    while(my $addon = readdir($dir)) {
        next if $addon eq '.' or $addon eq '..' or $addon eq 'CVS' or $addon eq '.cvsignore';
        my $conf  = catfile($root, 'addons', $addon, 'conf', 'class.conf');
        if (-e $conf) {
            $pkg->load_file($conf);
        }
    }
}

sub load_file {
    my ($pkg, $file) = @_;
    my $conf = Config::ApacheFormat->new(
                 hash_directives => ['setclass']);
    eval { $conf->read($file) };
    croak("Unable to load class configuration file $file: $@") if $@;

    my @keys = $conf->get('setclass');
    foreach my $key (@keys) {
        $CLASSES{$key} = $conf->get('setclass', $key);
    }
}


BEGIN { __PACKAGE__->load_configuration() }


1;
