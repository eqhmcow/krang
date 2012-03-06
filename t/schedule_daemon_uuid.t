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
my %stale_schedule_id;
my %foreign_stale_schedule_id;

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
                my $sched = pkg('Schedule::Action::clean')->new(
                    action      => 'clean',
                    object_type => 'tmp',
                    repeat      => 'daily',
                    hour        => 3,
                    minute      => 0,
                    daemon_uuid => hostname . '_1234567890',
                );
                $sched->save();

                warn sprintf '# set stale claim schedule_id %s with daemon_uuid %s %s',
                  $sched->schedule_id,
                  $sched->daemon_uuid,
                  pkg('Conf')->instance();

                $stale_schedule_id{$instance} = $sched->schedule_id;

                # set a stale schedule that should not be cleared on startup
                my $foreign_sched = pkg('Schedule::Action::clean')->new(
                    action      => 'clean',
                    object_type => 'tmp',
                    repeat      => 'daily',
                    hour        => 3,
                    minute      => 0,
                    daemon_uuid => 'not' . hostname . '_1234567890',
                );
                $foreign_sched->save();

                warn sprintf '# set stale claim schedule_id %s with daemon_uuid %s %s',
                  $foreign_sched->schedule_id,
                  $foreign_sched->daemon_uuid,
                  pkg('Conf')->instance();

                $foreign_stale_schedule_id{$instance} = $foreign_sched->schedule_id;
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

my @schedules;

my $creator = pkg('Test::Content')->new();

my $found_sched;
my $cnt = 0;

foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);

    # look for our stale schedule and check that daemon_uuid is cleared
    # the scheduler might block find(), so try 3 times
    while (1) {
        last if $cnt++ > 3;
        ($found_sched) = pkg('Schedule')->find(schedule_id => $stale_schedule_id{$instance});
        if ($found_sched) {
            push @schedules, $found_sched;
            last;
        }
        sleep $scheduler_sleep_interval;
    }
    ok($found_sched, "stale schedule that had our hostname should still exist");
    is($found_sched->schedule_id, $stale_schedule_id{$instance}, "stale schedule found");
    is($found_sched->daemon_uuid, undef, "stale schedule for our hostname should have daemon_uuid cleared");

    # look for the foreign stale schedule and check that daemon_uuid is not cleared
    # the scheduler might block find(), so try 3 times
    while (1) {
        last if $cnt++ > 3;
        ($found_sched) = pkg('Schedule')->find(schedule_id => $foreign_stale_schedule_id{$instance});
        if ($found_sched) {
            push @schedules, $found_sched;
            last;
        }
        sleep $scheduler_sleep_interval;
    }
    ok($found_sched, "stale schedule with another hostname should still exist");
    is($found_sched->schedule_id, $foreign_stale_schedule_id{$instance}, "stale schedule for another hostname should not cleared");
    is($found_sched->daemon_uuid, 'not'.hostname.'_1234567890', "stale schedule for another hostname should not have daemon_uuid cleared");
}

END {

    foreach (@schedules) {
        $_->delete;
    }

    $creator->cleanup();
}
