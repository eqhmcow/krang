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
use Krang::Conf qw(KrangRoot ScheduleInterval ScheduleLog);
use Krang::Schedule;

#
# Package Variables
####################
# Constants
############
use constant SLEEP_INTERVAL => ScheduleInterval;

# Globals
##########
# child of 'Proc::Daemon';
our @ISA = 'Proc::Daemon';

# log handle
our $log;

# log path
our $logpath = File::Spec->catfile(KrangRoot,
                                   'logs',
                                   ScheduleLog || 'schedule.log');

# pidfile path
our $pidfile = File::Spec->catfile($ENV{KRANG_ROOT},
                                   'tmp',
                                   'schedule_daemon.pid');

# handle SIGTERM
$SIG{'TERM'} = sub {
    # remove pidfile if it exists
    unlink $pidfile if -e $pidfile;

    # print ending message and close if $log is defined
    if (defined $log) {
        my $now = localtime;
        $log->print("[$now] SCHEDULE DAEMON STOPPED.\n\n");
        $log->close;
    }

    # get out of here
    exit();
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

    # do forking bit see Proc::Daemon
    $self->SUPER::Init;

    # drop of pidfile
    my $fh = IO::File->new(">$pidfile");
    croak(__PACKAGE__ . "->run() unable to write pidfile.")
      unless defined $fh;
    $fh->print($$);
    $fh->close();

    # open log
    $log = IO::File->new(">>$logpath");
    croak(__PACKAGE__ . "->run() unable to open log for appending .")
      unless defined $log;

    # autoflush
    $log->autoflush();

    # print kickoff message
    my $now = localtime;
    $log->print("\n[$now] SCHEDULE DAEMON STARTED\n");

    # time compare vars
    my ($after, $before, $sleep);

    # loop forever :)
    while (1) {
        $before = localtime;

        my @schedule_ids = Krang::Schedule->run($log);

        # log activity
        if (@schedule_ids) {
            $log->print("[$before] Ran ids: " . join(",", @schedule_ids) .
                        "\n");
        } else {
            $log->print("[$before] No objects run.\n");
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
