package Krang::Schedule::Daemon;

=head1 NAME

Krang::Schedule::Daemon - Module that periodically calls Krang::Schedule->run


=head1 SYNOPSIS

  use Krang::Schedule::Daemon;


=head1 DESCRIPTION

This module purpose in life it to call Krang::Schedule->run every
Krang::Conf->ScheduleSleepInterval seconds.  On termination, deletes its
pidfile and exits.

=cut


#
# Pragmas/Module Dependencies
##############################
# Pragmas
##########
use strict;
use warnings;

# External Modules
###################
use Carp qw(croak);
use File::Spec;
use IO::File;
use Proc::Daemon;
use Time::Piece;
use Time::Seconds;


# Internal Modules
###################
use Krang::Conf;


#
# Package Variables
####################
# Constants
############
use constant SLEEP_INTERVAL => Krang::Conf->ScheduleSleepInterval();

# Read-only fields
use constant DAEMON_RO => qw();

# Read-write fields
use constant DAEMON_RW => qw();

# Globals
##########
# child of 'Proc::Daemon';
our @ISA = 'Proc::Daemon';

# pidfile path
our $pidfile = File::Spec->catfile($ENV{KRANG_ROOT},
                                   'tmp',
                                   'schedule_daemon.pid');


# handle SIGTERM
$SIG{'TERM'} = sub {
    # remove pidfile if it exists
    unlink $pidfile if -e $pidfile;

    # get out of here
    exit();
};

# Lexicals
###########


=head1 INTERFACE

=head2 FIELDS

=head2 METHODS

=over

=item C<< Krang::Schedule::Daemon->run >>

Method to kick off the scheduling daemon.  It does the following:
  * writes out its pidfile to $KRANG_ROOT/tmp/schedule_daemon.pid
  * loops indefinitely calling Krang::Schedule->run() and then sleeping for
    the difference in time between the sleep interval and the time spent during
    run().

=back

=cut

sub run {
    my $self = shift;

    $self->SUPER::Init;

    my $fh = IO::File->new(">$pidfile");
    croak(__PACKAGE__ . "->run() unable to write pidfile.")
      unless defined $fh;
    $fh->print($$);
    $fh->close();

    # time compare vars
    my ($after, $before);

    # loop forever :)
    while (1) {
        $before = localtime;

        Krang::Schedule->run();

        $after = localtime;

        sleeep(SLEEP_INTERVAL - ($after - $before));
    }
}


=head1 TO DO

=head1 SEE ALSO

=cut


my $quip = <<QUIP;
1
QUIP
