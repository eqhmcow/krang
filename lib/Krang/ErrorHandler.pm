package Krang::ErrorHandler;
use strict;
use warnings;
use Krang::Log qw(critical debug);

BEGIN {
    $SIG{__DIE__} = sub {
        my $in_eval = 0;
        for(my $stack = 1; my $sub = (CORE::caller($stack))[3]; $stack++) {
            $in_eval = 1 if $sub =~ /^\(eval\)/;
        }
        return if $in_eval;
        my $err = shift;
        critical $err;
        die $err;
    };
    $SIG{__WARN__} = sub {
        my $warn = shift;
        debug $warn;
        print STDERR $warn;
    };
}

1;

__END__

=head1 NAME

Krang::ErrorHandler - consistent die() and warn() handlers for Krang

=head1 SYNOPSIS

At the top of your script or module:

  use Krang::ErrorHandler;

=head1 DESCRIPTION

When you use this module, $SIG{__DIE__} and $SIG{__WARN__} handlers
are setup such that all die() and warn() messages are sent to
Krang::Log.  This does not alter their operation - die() still really
die()s and warn() still prints to STDERR.

Note that Krang::Script uses Krang::ErrorHandler, so test scripts
don't need to use this module explicitely.  However, CGI scripts do
because when run under mod_cgi they will run in their own process.

=head1 INTERFACE

None.

=cut
