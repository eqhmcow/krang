package Krang::Profiler;
use strict;
use warnings;

use Devel::Profiler 
  package_filter => \&package_filter;

sub package_filter {
    local $_ = shift;

    # must accept main to see anything
    return 1 if /^main$/;

    # ignore Krang::Conf - it plays symbol table games that confuse
    # Devel::Profiler
    return 0 if /^Krang::Conf$/;

    # ignore Exception::Class kids
    return 0 if UNIVERSAL::isa($_, "Exception::Class::Base");

    # profile all other Krang modules
    return 1 if /^Krang/;

    # ignore everything else
    return 0;
}

=head1 NAME

Krang::Profiler - Devel::Profiler wrapper for Krang

=head1 SYNOPSIS

  use Krang::Profiler;

=head1 DESCRIPTION

This module provides a wrapper around Devel::Profiler setup to work
correctly with Krang.  To use this module set the environment variable
KRANG_PROFILE to 1 and run the script you wish to profile.  Don't
forget to use Krang::Script since that's how this module gets
activated.

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
