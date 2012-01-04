package Krang::Schedule::Daemon;

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use IO::File;
use Proc::Daemon;
use POSIX ":sys_wait_h";

use Carp qw(croak);
use Time::Piece;
use Time::Seconds;

use Krang::ClassLoader Conf =>
  qw(KrangRoot instance instances SchedulerMaxChildren SchedulerDefaultFailureDelay SMTPServer FromAddress DisableScheduler);
use Krang::ClassLoader Log => qw/critical debug info reopen_log/;
use Krang::ClassLoader 'Schedule';
use Krang::ClassLoader DB => qw(dbh forget_all_dbhs);
use Krang::ClassLoader 'Cache';

my $pidfile = File::Spec->catfile(KrangRoot, 'tmp', 'schedule_daemon.pid');

use constant CHUNK_SIZE     => 5;
use constant SLEEP_INTERVAL => 1;

my $CHILD_COUNT   = 0;
my %child_pids    = ();
my %assigned_jobs = ();

use Sys::Hostname qw(hostname);
my $daemon_uuid;
BEGIN { $daemon_uuid = hostname . '_' . $$ }

# handle SIGTERM
$SIG{'TERM'} = sub {

    info(__PACKAGE__ . " caught SIGTERM.");

    _kill_children();

    # remove pidfile if it exists
    unlink $pidfile if -e $pidfile;

    info(__PACKAGE__ . " Exiting.");
    _clear_my_daemon_uuid_claims();

    # get out of here
    exit(0);
};

=head1 NAME

Krang::Schedule::Daemon - Module to handle scheduled tasks in Krang.

=head1 SYNOPSIS

  use Krang::ClassLoader 'Schedule::Daemon';

  pkg('Schedule::Daemon')->run();

=head1 DESCRIPTION

This module is responsible for creating a daemon whose task is to run
all scheduled tasks in Krang.

When started (using the C<run()> method), Krang::Schedule::Daemon
creates a persistant daemon (whose PID file can be found at
KRANG_ROOT/tmp/schedule_daemon.pid).  Once started, the daemon will
poll L<Krang::Scheduler> at a set interval (defaults to 1 second ---
Is this something we want settable in KrangConf??), looking for jobs
that need to be executed.  If none are found, the daemon will sleep
for another interval, wake up, and repeat the process.

If jobs are found, Krang::Schedule::Daemon will sort and group them
based on priority, next_run time, and resource usage.  Once sorted and
grouped, jobs will be handed off to child processes that will actually
handle execution.

When a child process exits (all tasks have been completed, or a fatal
error occurred), the parent daemon will make a note of the child
exiting and clear its entry from the internal table tracking all work
being done.

There is a limit to the number of children that can run
simultaneously, determined by the L<Krang::Conf> config file directive
B<ScheduleMaxChildren>.

Multiple schedulers (on multiple machines) can be run without
interfering with each other.

=head2 Job Execution

When a group of jobs is ready to be executed, a child process is
spawned to handle the work.  The workload assigned to the child
process is determined by the parent daemon, and the work is completed
in order of priority.

Once spawned, the parent daemon makes entries in the
C<%active_children> and C<%assigned_jobs> hashes.  C<%active_children>
is keyed by child PID, and each entry contains a list of
L<Krang::Schedule> IDs currently being processed by that child.
C<%assigned_jobs> is the opposite hash, keyed by Krang::Schedule IDs,
where each key points to the child PID of the child process handling
the job.  These two hashes exist to keep Krang::Schedule::Daemon from
assigning work-in-progress to new children.


=head2 Priority

The Priority of a job entry determines when it will get executed in
relation to all other pending jobs.  Priority is stored in the
L<Krang::Schedule> object as an integer value.

Priority will be adjusted by Krang::Schedule::Daemon, based on whether
or not the next scheduled execution (next_run) of a job was met
(e.g. if the value of job->next_run() < now(), the execution was
missed).

If scheduled execution was missed, the priority of the job will be
bumped up by 1, unless it is more than 1 hour late, when it is bumped
by 2.  This will not necessarily put the job at the front of the line,
but it will get it executed sooner than it would have been.


=head2 Cleanup

When a child finishes an individual task, C<<
Krang::Schedule->mark_as_completed($task_id) >> will be called,
updating the entry in the database.  L<Krang::Schedule> will determine
what the new entry in the database will look like, based on whether or
not the job is a re-occuring one.

Once a child has completed all tasks assigned to it, the child will
exit.  The parent daemon will trap the SIG_CHLD signal sent by the
exiting child, and remove that child PID and all L<Krang::Schedule>
entries from the C<%active_children> and C<%assigned_jobs> hashes.


=head1 INTERFACE

=over

=item C<< run() >>

Starts the L<Krang::Schedule::Daemon> daemon.  Once started, it
periodically (1 second) polls the databases fore each instance,
looking for



Creates a pid file at KRANG_ROOT/tmp/schedule_daemon.pid with the
process ID of the daemon itself.

The daemon can be killed by sending a SIG_TERM (e.g. kill) signal.

=cut

sub run {

    my $self = shift;

    # create the daemon.
    Proc::Daemon::Init;

    # reopen the logfile
    reopen_log();

    # forget old dbh from parent process
    forget_all_dbhs();

    # drop off pidfile
    my $pidfile = IO::File->new(">$pidfile");
    unless (defined($pidfile)) {
        my $msg = __PACKAGE__ . "->run() unable to write '$pidfile'.  Exiting.";
        critical($msg);
        exit();
    }
    $pidfile->print($$);
    $pidfile->close();

    # print kickoff message
    my $now = localtime;
    info(__PACKAGE__ . " started.");

    # keep a hash of system users
    my %system_user;

    while (1) {

        debug(__PACKAGE__ . "->run(): heartbeat. $CHILD_COUNT child processes active");

        # make sure there's nothing dead left out there.
        _reap_dead_children() if ($CHILD_COUNT);

        foreach my $instance (pkg('Conf')->instances) {

            # switch instance and reset REMOTE_USER to the system user
            # for this instance, needed for permissions checks
            pkg('Conf')->instance($instance);
            if (DisableScheduler) {
                debug('DisableScheduler directive is in effect for this instance.');
                next;
            }
            unless ($system_user{$instance}) {
                ($system_user{$instance}) = pkg('User')->find(
                    login    => 'system',
                    ids_only => 1
                );
            }
            $ENV{REMOTE_USER} = $system_user{$instance};

            my @jobs = _query_for_jobs();

            if (@jobs) {
                debug(sprintf("%s: %i Pending jobs found.", __PACKAGE__, ($#jobs + 1)));
            }

            if (@jobs) {
                scheduler_pass(@jobs);
            }
        }

        sleep SLEEP_INTERVAL;
    }
}

=item C<< scheduler_pass() >>

Polls the schedule database for a given L<Krang::Conf> instance,
looking for jobs where next_run <= now.

If work to be done is found, a child process is allocated to take care
of the tasks at hand.

When a child process is spawned, it will C<execute()> all work in the
order assigned.  When a task is completed, it is marked as complete,
and updated if necessary.  Any jobs that fail will be trapped and
skipped, and the work continues.  When a child is finished, it will
exit.

When a child exits, C<scheduler_pass()> will clean up, removing its
entry from the tables tracking work being done.

If there is more work to be done than available child processes,
C<scheduler_pass()> will block until a child returns, complete
cleanup, and then spawn a new child to handle the pending work.

Returns when all work has been assigned.  The first task on the next
run will be to reap newly-dead (e.g. finished) children.

=cut

sub scheduler_pass {

    my @jobs = @_;

    #    our $CHILD_COUNT;

    my $instance = pkg('Conf')->instance();

    # cleanup - make sure there's nothing dead left out there.
    _reap_dead_children() if ($CHILD_COUNT);

    info(
        sprintf(
            "%s->scheduler_pass('%s'): %i jobs found.  Working..",
            __PACKAGE__, $instance, ($#jobs + 1)
        )
    );

    my $pid;

    # wait for a child to return.
    if ($CHILD_COUNT >= SchedulerMaxChildren) {
        _reap_dead_children(1);
    }

    # fork a child to take care of the work.
    if ($pid = fork) {
        _parent_work($pid, \@jobs);
    } elsif (defined($pid)) {

        # change handling of SIGTERM -- don't act like your parents!
        $SIG{'TERM'} = sub {
            debug(__PACKAGE__ . ": Child caught SIGTERM.  Exiting.");
            exit(0);
        };
        _child_work(\@jobs);

    } else {
        critical(__PACKAGE__ . "->run($instance): Cannot fork children: $!");
    }

    if ($CHILD_COUNT) {
        debug(
              sprintf(
                      "%s STATUS: %i children running.",
                      __PACKAGE__, $CHILD_COUNT
                     )
             );
    }
}

#
# same functionality as if the daemon was killed.
#
sub stop {

    # remove pidfile if it exists
    unlink $pidfile if -e $pidfile;

    info(__PACKAGE__ . "->stop(): Exiting.");

    # get out of here
    exit(0);

}

#
# _child_work(\@tasks);
#
# Handles the work assigned the newly-spawned child.  Runs through @tasks, executing all of them.
#
sub _child_work {

    my $tasks = shift;

    my $instance = pkg('Conf')->instance();

    # lose the parent's DB handle.
    forget_all_dbhs();

    # reopen the log file
    reopen_log();

    # start the cache
    pkg('Cache')->start();
    eval {

        # child
        debug(
            sprintf(
                "%s: Child PID=%i spawned with Schedule IDs=%s.",
                __PACKAGE__, $$, (join ', ', (map { $_->schedule_id } @$tasks))
            )
        );

        foreach my $t (@$tasks) {
            debug(
                sprintf(
                    "%s->_child_work('%s'): Child PID=%i running schedule_id=%i",
                    __PACKAGE__, $instance, $$, $t->schedule_id()
                )
            );
            eval { $t->execute(); };
            if (my $err = $@) {

                # job failed, so, if it didn't delete the schedule object 
                # (which would prevent us from doing anything)..
                if (
                    $t
                    && (my ($still_in_db) =
                        (pkg('Schedule')->find(count => 1, schedule_id => $t->schedule_id)))
                  )
                {
                    chomp($err);
                    $err = '"' . $err . '"';
                    my $delay_btw_tries = $t->failure_delay_sec
                      || SchedulerDefaultFailureDelay
                      || 60;
                    if (defined $t->failure_max_tries) {
                        if ($t->failure_max_tries > 1) {

                            # this job hasn't yet reached its maximum # of failures
                            $t->{failure_max_tries}--;
                            $t->{next_run} = (Time::Piece->new + $delay_btw_tries)->mysql_datetime;
                            $t->{daemon_uuid} = undef;
                            $t->save;
                            critical(
                                sprintf(
                                    "%s->_child_work('%s'): PID %i encountered error below with Schedule %i - TRIES LEFT: %d (NEXT IN %d SEC)\n%s",
                                    __PACKAGE__,           $instance,
                                    $$,                    $t->schedule_id(),
                                    $t->failure_max_tries, $delay_btw_tries,
                                    $err
                                )
                            );
                        } else {

                            # this job has reached its maximum # of failures
                            critical(
                                sprintf(
                                    "%s->_child_work('%s'): PID %i encountered error below with Schedule %i - GIVING UP!\n%s",
                                    __PACKAGE__, $instance, $$, $t->schedule_id(), $err
                                )
                            );

                            # since we're giving up, notify user if possible
                            if ($t->failure_notify_id) {
                                critical("WILL ATTEMPT TO NOTIFY USER "
                                      . $t->failure_notify_id
                                      . " VIA EMAIL");
                                _notify_user(
                                    $t->failure_notify_id,
                                    $t->failure_subject($err),
                                    $t->failure_message($err)
                                );
                            }
                            $t->delete;
                        }
                    } else {

  # this job has no maximum # of failures set, so we don't notify user; we're going to keep trying..
                        $t->{next_run} = (Time::Piece->new + $delay_btw_tries)->mysql_datetime;
                        $t->{daemon_uuid} = undef;
                        $t->save;
                        critical(
                            sprintf(
                                "%s->_child_work('%s'): PID %i encountered error below with Schedule %i - WILL KEEP TRYING EVERY %d SEC\n%s",
                                __PACKAGE__,       $instance,        $$,
                                $t->schedule_id(), $delay_btw_tries, $err
                            )
                        );
                    }
                }
            } elsif ($t->success_notify_id) {
                $t->{daemon_uuid} = undef;
                $t->save;
                _notify_user($t->success_notify_id, $t->success_subject, $t->success_message);
            } else {
                $t->{daemon_uuid} = undef;
                $t->save;
            }
        }
    };
    my $err = $@;

    # turn cache off
    pkg('Cache')->stop();

    die $err if $err;

    debug(sprintf("%s: Child PID=%i finished.  Exiting.", __PACKAGE__, $$));

    exit(0);

}

# helper function - passed a user_id, subject, and msg, send the user an email with the subject & message
sub _notify_user {
    my ($user_id, $subject, $msg) = @_;
    if (my $user = (pkg('User')->find(user_id => $user_id))[0]) {
        if (my $email_to = $user->email) {
            my $sender =
              Mail::Sender->new({smtp => SMTPServer, from => FromAddress, on_errors => 'die'});
            $sender->MailMsg({to => $email_to, subject => $subject, msg => $msg});
        }
    }
}

#
# _parent_work($pid, \@tasks)
#
# Handles the bookkeeping done by the parent after the fork().
#
# This means making PID and scheduleID entries in global hashes,
# incrementing the child counter.
#

sub _parent_work {

    my ($pid, $tasks) = @_;

    my $instance = pkg('Conf')->instance();

    # parent
    foreach my $t (@$tasks) {
        $assigned_jobs{$instance}{$t->schedule_id} = $pid;
        push @{$child_pids{$pid}{jobs}}, $t->schedule_id;
    }
    $child_pids{$pid}{instance} = $instance;

    $CHILD_COUNT++;

}

#
# _reap_dead_children($block)
#
# Polls waitpid() for dead children.  If none are found, it returns immediately.
# If $block is set to 1, and children exist, it will block until children return.
# If a dead child is found, it cleans the entries out of the %child_pids and %assigned_jobs tables.
#

sub _reap_dead_children {

    my $block = shift || 0;

    #    our $CHILD_COUNT;

    debug(__PACKAGE__ . "->_reap_dead_children(): $CHILD_COUNT children out there.");

    my $child_pid;

    if ($block) {

        # blocking, waiting for one to return.
        $child_pid = waitpid(-1, 0);

        if ($child_pid == -1 && $CHILD_COUNT) {
            info(__PACKAGE__
                  . " ERROR: $CHILD_COUNT processes are supposed to be working, 0 found.");
        } elsif ($child_pid > 0) {

            # reap it.
            _cleanup_tables($child_pid);
            $CHILD_COUNT--;
        }
    } else {

        # cleanup - reap everything that returns.
        while (($child_pid = waitpid(-1, &WNOHANG)) != -1) {

            last if ($child_pid == 0);

            _cleanup_tables($child_pid);
            $CHILD_COUNT--;

        }
    }

    debug(__PACKAGE__ . "->_reap_dead_children(): $CHILD_COUNT children remaining.");

}

#
# _kill_children()
#
# Such violence!
#
#
# Called when the parent needs to exit.
# Attempts to reap dead children first, and then sends SIGTERM to all
# children.  Checks to see if they're still around, and follows up
# with a SIGKILL if needed.
#

sub _kill_children {

    #    our %child_pids;

    _reap_dead_children();

    my @kids;

    @kids = keys %child_pids;

    if (@kids) {

        info(__PACKAGE__ . " killing child processes.");

        kill 'TERM', @kids;

        # wait a couple of seconds to see if kids are dead.
        # if they're still alive, send SIGKILL.

        sleep 3;

        foreach my $kid (@kids) {
            if (kill 0 => $_) {
                debug(__PACKAGE__ . ": child PID=$kid ignored TERM signal.");
                kill 'KILL', $kid;
            }
        }
    }

}

sub _cleanup_tables {

    my $child_pid = shift;

    #    our %child_pids;
    #    our %assigned_jobs;

    my @sched_ids;
    my $instance = $child_pids{$child_pid}{instance};

    foreach my $sched_id (@{$child_pids{$child_pid}{jobs}}) {
        push @sched_ids, $sched_id;
        delete $assigned_jobs{$instance}{$sched_id};
    }
    delete $child_pids{$child_pid};

    debug(
        sprintf(
            "%s: child PID=%i reaped.  Completed schedule IDs ('%s'): %s",
            __PACKAGE__, $child_pid, $instance, (join ',', @sched_ids)
        )
    );

}

#
# _cull_running_jobs(\@schedules);
#
# Given a list of schedule objects, check %assigned_jobs to make sure
# none of them are already being processed.  Return a list of schedule
# objects that have not already been assigned.
#

sub _cull_running_jobs {

    my $schedules = shift;

    #    our %assigned_jobs;

    my $instance = pkg('Conf')->instance();

    my @new_jobs;

    foreach my $sched (@$schedules) {
        next if (exists($assigned_jobs{$instance}{$sched->schedule_id}));
        push @new_jobs, $sched;
    }

    return @new_jobs;
}

#
# _query_for_jobs
#
# Searches the Schedule database for jobs that need to be run now.
#

sub _query_for_jobs {

    my $now = localtime();

    my @schedules;

    @schedules = pkg('Schedule')->find(
        next_run_less_than_or_equal => $now->mysql_datetime,
        order_by                    => 'priority',
        select_for_update           => 1,
        daemon_uuid                 => undef,
        limit                       => CHUNK_SIZE,
    );

    # update the schedules with the daemon's uuid
    for my $schedule (@schedules) {
        $schedule->daemon_uuid($daemon_uuid);
        $schedule->save;
    }

    my $dbh = dbh();

    # commit
    $dbh->commit or critical( 'error during commit : ' . $dbh->errstr);

    # disconnect this handle since it has AutoCommit => 0 set
    $dbh->disconnect or critical('error during disconnect : '. $dbh->errstr);

    return _cull_running_jobs(\@schedules);

}

#
# _clear_my_daemon_uuid_claims
#
# Searches all instances' Schedule database for jobs with our daemon_uuid and clears that value
#

sub _clear_my_daemon_uuid_claims {
    debug(__PACKAGE__ . "->_clear_my_daemon_uuid_claims() daemon_uuid is $daemon_uuid");

    foreach my $instance (pkg('Conf')->instances) {

        my @schedules;

        @schedules = pkg('Schedule')->find(
            select_for_update           => 1,
            daemon_uuid                 => $daemon_uuid,
        );

        # update the schedules with the daemon's uuid
        for my $schedule (@schedules) {
            debug(__PACKAGE__ . "->_clear_my_daemon_uuid_claims() releasing " . $schedule->schedule_id);
            $schedule->daemon_uuid(undef);
            $schedule->save;
        }

        my $dbh = dbh();

        # commit
        $dbh->commit or critical( 'error during commit : ' . $dbh->errstr);

        # disconnect this handle since it has AutoCommit => 0 set
        $dbh->disconnect or critical('error during disconnect : '. $dbh->errstr);

    }
}

=back

=head1 TODO


=head1 SEE ALSO

L<Krang::Schedule>, L<Krang::Alert>, L<Krang::Publisher>


=cut

my $quip = <<END;

There is a Reaper whose name is Death, And, with his sickle keen,
He reaps the bearded grain at a breath, And the flowers that grow between.

"Shall I have nought that is fair?" saith he; "Have nought but the bearded grain?
Though the breath of these flowers is sweet to me, I will give them all back again."

He gazed at the flowers with tearful eyes, He kissed their drooping leaves;
It was for the Lord of Paradise He bound them in his sheaves.

"My Lord has need of these flowers gay," The Reaper said, and smiled;
"Dear tokens of the earth are they, Where he was once a child.

"They shall all bloom in fields of light, Transplanted by my care,
And saints, upon their garments white, These sacred blossoms wear."

And the mother gave, in tears and pain, The flowers she most did love;
She knew she should find them all again In the fields of light above.

O, not in cruelty, not in wrath, The Reaper came that day;
'Twas an angel visited the green earth, And took the flowers away.


            "The Reaper And The Flowers"
            Henry Wadsworth Longfellow

END

