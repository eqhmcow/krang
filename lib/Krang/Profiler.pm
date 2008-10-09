package Krang::Profiler;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

# make sure to load element sets first so they can be profiled
use Krang::ClassLoader 'ElementLibrary';

# get a list of element sets for all instances
use Krang::ClassLoader Conf => qw(InstanceElementSet);
our @ELEMENT_SETS;

BEGIN {
    my $old = pkg('Conf')->instance();
    foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        push(@ELEMENT_SETS, InstanceElementSet);
    }
    pkg('Conf')->instance($old);
}

use Devel::Profiler package_filter => \&package_filter;

sub package_filter {
    local $_ = shift;

    # must accept main to see anything
    return 1 if /^main$/;

    # ignore Krang::Conf - it plays symbol table games that confuse
    # Devel::Profiler
    return 0 if /^pkg('Conf')$/;

    # ignore Exception::Class kids
    return 0 if UNIVERSAL::isa($_, "Exception::Class::Base");

    # profile all other Krang modules
    return 1 if /^Krang/;

    # profile element libraries
    foreach my $set (@ELEMENT_SETS) {
        return 1 if /^$set/;
    }

    # ignore everything else
    return 0;
}

=head1 NAME

Krang::Profiler - Devel::Profiler wrapper for Krang

=head1 SYNOPSIS

  KRANG_PROFILE=1 ./script_to_profile.pl

=head1 DESCRIPTION

This module provides a wrapper around Devel::Profiler setup to work
correctly with Krang.  To use this module set the environment variable
KRANG_PROFILE to 1 and run the script you wish to profile.  Don't
forget to use Krang::Script since that's how this module gets
activated.

B<NOTE:> Do not use Krang::Profiler directly unless you want profiling
to be turned on all the time.

This module sets up Devel::Profiler to only profile subroutines in the
Krang hierarchy.  That means that calls that Krang makes to external
modules are rolled into the Krang subroutine that calls them.  For
example, if your method Krang::Foo::bar() makes ten calls to DBI that
take 1 second each and does no other processing then Krang::Foo::bar()
will appear in the profile as taking 10 seconds.  The DBI methods will
not appear.

=head1 INTERFACE

None.

=cut

1;
