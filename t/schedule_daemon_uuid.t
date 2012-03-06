use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Carp;
use File::Spec::Functions;
use File::Path;
use IO::File;
use Storable qw/freeze thaw/;
use Sys::Hostname qw(hostname);

use Time::Piece;
use Time::Piece::MySQL;
use Time::Seconds;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(KrangRoot InstanceElementSet SchedulerMaxChildren SchedulerSleepInterval);
use Krang::ClassLoader 'Schedule';
use Krang::ClassLoader 'Test::Content';

use Data::Dumper;

my $pidfile;
my $scheduler_sleep_interval = SchedulerSleepInterval || 5; # 5 is the default value (defined in Krang::Schedule::Daemon)

my $stop_daemon;
my $schedulectl;
my %this_host_stale_schedule_id;
my %other_host_stale_schedule_id;

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

BEGIN {

    my $found;

    $pidfile     = File::Spec->catfile(KrangRoot, 'tmp', 'schedule_daemon.pid');
    $schedulectl = File::Spec->catfile(KrangRoot, 'bin', 'krang_schedulectl');
    $stop_daemon = 0;

    foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        if ((InstanceElementSet eq 'TestSet1') and (SchedulerMaxChildren > 0)) {
            eval 'use Test::More qw(no_plan)';
            $found = 1;
            last;
        }
    }

    if ($found) {
        unless (-e $pidfile) {
            # add a stale daemon_uuid claim on a schedule entry
            use_ok(pkg('Schedule::Action'));
            use_ok(pkg('Schedule::Action::clean'));

            foreach my $instance (pkg('Conf')->instances) {
                pkg('Conf')->instance($instance);

                # set a stale schedule that should be cleared on startup
                my $this_host_sched = pkg('Schedule::Action::clean')->new(
                    action      => 'clean',
                    object_type => 'tmp',
                    repeat      => 'daily',
                    hour        => 3,
                    minute      => 0,
                    daemon_uuid => hostname . '_1234567890',
                );
                $this_host_sched->save();
                $this_host_stale_schedule_id{$instance} = $this_host_sched->schedule_id;

                # set a stale schedule that should not be cleared on startup
                my $other_host_sched = pkg('Schedule::Action::clean')->new(
                    action      => 'clean',
                    object_type => 'tmp',
                    repeat      => 'daily',
                    hour        => 3,
                    minute      => 0,
                    daemon_uuid => 'not' . hostname . '_1234567890',
                );
                $other_host_sched->save();
                $other_host_stale_schedule_id{$instance} = $other_host_sched->schedule_id;
            }

            # start the scheduler
            `$schedulectl start`;
            $stop_daemon = 1;
            sleep 5;

            unless (-e $pidfile) {
                note('Scheduler Daemon Startup failed.  Exiting.');
                exit(1);
            }
        }
        eval 'use Test::More qw(no_plan)';
    } elsif (SchedulerMaxChildren == 0) {
        eval
          "use Test::More skip_all => 'SchedulerMaxChildren set to 0 -- schedule daemon will not run';";
    } else {
        eval "use Test::More skip_all => 'test requires a TestSet1 instance';";
    }
}

END {
    if ($stop_daemon) {
        `$schedulectl stop`;
    }
}


my $creator = pkg('Test::Content')->new();

my $this_host_found_sched;
my $other_host_found_sched;
my $cnt = 0;

foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);

    my @schedules;
    # look for our stale schedule and check that daemon_uuid is cleared
    # the scheduler might block find(), so try 3 times
    while (1) {
        last if $cnt++ > 3;
        ($this_host_found_sched) = pkg('Schedule')->find(schedule_id => $this_host_stale_schedule_id{$instance});
        if ($this_host_found_sched) {
            push @schedules, $this_host_found_sched;
            last;
        }
        sleep $scheduler_sleep_interval;
    }
    ok($this_host_found_sched, "stale schedule that had our hostname should still exist");
    SKIP: {
        skip('we did not find the schedule entry', 2)
          unless ($this_host_found_sched);
        is($this_host_found_sched->schedule_id, $this_host_stale_schedule_id{$instance}, "stale schedule found");
        is($this_host_found_sched->daemon_uuid, undef, "stale schedule for our hostname should have daemon_uuid cleared");
    }

    # look for the other_host stale schedule and check that daemon_uuid is not cleared
    # the scheduler might block find(), so try 3 times
    while (1) {
        last if $cnt++ > 3;
        ($other_host_found_sched) = pkg('Schedule')->find(schedule_id => $other_host_stale_schedule_id{$instance});
        if ($other_host_found_sched) {
            push @schedules, $other_host_found_sched;
            last;
        }
        sleep $scheduler_sleep_interval;
    }
    ok($other_host_found_sched, "stale schedule with another hostname should still exist");
    SKIP: {
        skip('we did not find the schedule entry', 2)
          unless ($other_host_found_sched);
        is($other_host_found_sched->schedule_id, $other_host_stale_schedule_id{$instance}, "stale schedule for another hostname should not cleared");
        is($other_host_found_sched->daemon_uuid, 'not'.hostname.'_1234567890', "stale schedule for another hostname should not have daemon_uuid cleared");
    }

    foreach (@schedules) {
        $_->delete;
    }
}

END {
    $creator->cleanup();
}
