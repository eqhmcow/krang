package Krang::lib;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::lib - setup Krang library search path

=head1 SYNOPSIS

  use Krang::ClassLoader 'lib';

  # reload lib dirs when needed (ex. addon install)
  pkg('lib')->reload();

=head1 DESCRIPTION

This module is responsible for setting up the search path for Krang's
Perl libraries.  It handles setting @INC and $ENV{PERL5LIB} to correct
values.

B<NOTE>: Krang::lib is used by Krang::Script, so in most cases you
should just use Krang::Script and leave it at that.

=head1 INTERFACE

=head2 C<< Krang::lib->reload() >>

Call to reload library paths.  This is only needed when something new
is added, removal is handled automatically by Perl.

=cut

use Carp qw(croak);
use File::Spec::Functions qw(catdir);
use Config;

our $DONE = 0;

sub reload { 
    $DONE = 0;
    shift->import() 
}

sub import {
    return if $DONE; # this should only happen once unless reload() is called

    my $root = $ENV{KRANG_ROOT} 
      or croak("KRANG_ROOT must be defined before loading pkg('lib')");

    # prepend legacy element_lib/ first
    # (This will permit addons to override legacy behavior)
    my $legacy_elib = catdir($root, 'element_lib');
    $ENV{PERL5LIB} = $legacy_elib . 
      ($ENV{PERL5LIB} ? ":$ENV{PERL5LIB}" : "");
    unshift (@INC, $legacy_elib);
    
    # using Krang::Addon would be easier but this module shouldn't
    # load any Krang:: modules since that will prevent them from being
    # overridden in addons
    opendir(my $dir, catdir($root, 'addons'));
    while(my $addon = readdir($dir)) {
        next if $addon eq '.' or $addon eq '..';
        my $lib  = catdir($root, 'addons', $addon, 'lib');
        $ENV{PERL5LIB} = $lib . ":" . $ENV{PERL5LIB};
        unshift (@INC, $lib, "$lib/".$Config{archname});
    }

    $DONE = 1;
}

1;
