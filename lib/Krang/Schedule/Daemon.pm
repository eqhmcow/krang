package Krang::Schedule::Daemon;

=head1 NAME

Krang::Schedule::Daemon - Module that periodically calls Krang::Schedule->run


=head1 SYNOPSIS

  use Krang::Schedule::Daemon;


=head1 DESCRIPTION

This module's purpose in life it to call Krang::Schedule->run every
Krang::Conf->ScheduleInterval seconds.

It is started by calling the class method Krang::Schedule::Daemon->run.
On start it writes out a pidfile, opens a log, and loops indefinitely - making
its call to Krang::Schedule->run.  Activity is logged for each call to run.
If a process using this module is sent a TERM signal, it will remove its
pidfile and close its log.

=cut


# Start Daemon before loading Krang::Log or its file descriptor will be closed
BEGIN {
    use IO::File;
    use Proc::Daemon;
    Proc::Daemon::Init;
}


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
use Time::Piece;
use Time::Seconds;


# Internal Modules
###################
use Krang::Conf qw(KrangRoot CleanupInterval ScheduleInterval ScheduleLog);
use Krang::Log qw/critical debug info/;
use Krang::Schedule;

#
# Package Variables
####################
# Constants
############
use constant CLEANUP_INTERVAL => CleanupInterval;
use constant SLEEP_INTERVAL => ScheduleInterval;


# Globals
##########
# pidfile path
our $pidfile = File::Spec->catfile(KrangRoot, 'tmp', 'schedule_daemon.pid');

# handle SIGTERM
$SIG{'TERM'} = sub {
    # remove pidfile if it exists
    unlink $pidfile if -e $pidfile;

    debug("Removed Schedule Daemon pidfile.");
    debug("SCHEDULE DAEMON ENDED");

    # get out of here
    exit(0);
};


# Lexicals
###########


=head1 INTERFACE

=head2 METHODS

=over

=item C<< Krang::Schedule::Daemon->run >>

Method to kick off the scheduling daemon.  It does the following:
  * writes out its pidfile to $KRANG_ROOT/tmp/schedule_daemon.pid
  * loops indefinitely calling Krang::Schedule->run() and then sleeping for
    the difference in time between the sleep interval and the time spent during
    run().
A record of the Daemon's activity is written to its log which is configurable
through setting the ScheduleLog directive in krang.conf.

=back

=cut

sub run {
    my $self = shift;

    # drop off pidfile
    my $pidfile = IO::File->new(">$pidfile");
    croak(__PACKAGE__ . "->run() unable to write pidfile.")
      unless defined $pidfile;
    $pidfile->print($$);
    $pidfile->close();

    # print kickoff message
    my $now = localtime;
    debug("SCHEDULE DAEMON STARTED");

    # count of cleanup_attempts
    my $cleanups = 0;

    # time compare vars
    my ($after, $before, $sleep);

    # loop forever :)
    while (1) {
        $before = localtime;

        # run schedule objects every minute
        my @schedule_ids = Krang::Schedule->run();

        # attempt to clean_tmp and expire_sessions every
        # CLEANUP_INTERVAL minutes
        if (($cleanups == 0 ) ||
            (($before - ($now + (CLEANUP_INTERVAL * $cleanups))) >= 0)) {
            debug(__PACKAGE__ . ": attempting cleanup.");
            Krang::Schedule->clean_tmp();
            Krang::Schedule->expire_sessions();
            $cleanups++;
        }

        # log activity
        if (@schedule_ids) {
            debug(__PACKAGE__ . ": RAN SCHEDULE OBJECT IDS: " .
                 join(",", @schedule_ids));
        } else {
            debug(__PACKAGE__ . ": NO SCHEDULE OBJECTS RAN.");
        }

        $after = localtime;
        $sleep = SLEEP_INTERVAL - ($after - $before);

        # only sleep if $sleep is a positive integer
        sleep($sleep) if $sleep;
    }
}


=head1 TO DO

=head1 SEE ALSO

=cut


my $quip = <<QUIP;
1
QUIP
