use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Carp;
use File::Spec::Functions;
use File::Path;
use IO::File;
use Storable qw/freeze thaw/;

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

##################################################
## Presets

my $preview_url  = 'scheduletest.preview.com';
my $publish_url  = 'scheduletest.com';
my $preview_path = '/tmp/krangschedtest_preview';
my $publish_path = '/tmp/krangschedtest_publish';

my @schedules;

my $creator = pkg('Test::Content')->new();

my $site = $creator->create_site(
    preview_url  => $preview_url,
    publish_url  => $publish_url,
    preview_path => $preview_path,
    publish_path => $publish_path
);

# Make sure live templates are undeployed, create and deploy
# a set of test templates for publishing.
$creator->undeploy_live_templates();
$creator->deploy_test_templates();

END {

    foreach (@schedules) {
        $_->delete;
    }

    $creator->cleanup();
    rmtree $preview_path;
    rmtree $publish_path;
}

use_ok(pkg('Schedule::Daemon'));

# create story objects

my $num_stories = 5;

my $now = localtime;
my @stories;
my $trashed_story;
for my $num (1 .. $num_stories) {

    my $story = $creator->create_story();

    # trashed stories should not publish
    if ($num == 1) {
        $story->trash;
        $trashed_story = $story;
    } else {
        push @stories, $story;
    }

    my $sched = pkg('Schedule')->new(
        action      => 'publish',
        object_id   => $story->story_id(),
        object_type => 'story',
        repeat      => 'never',
        date        => $now
    );
    $sched->save();
    push @schedules, $sched;
}

# wait to see if it got published.
sleep ((10 * $scheduler_sleep_interval) + $num_stories);

foreach my $story (@stories) {
    my @paths = $creator->publish_paths(story => $story);

    foreach my $p (@paths) {
        ok(-e $p, 'story published');
    }
}

# trashed story should not be published
for my $p ($creator->publish_paths(story => $trashed_story)) {
    ok(!-e $p, "skipped scheduled publishing of trashed story");
}

# untrash and schedule-publish again
pkg('Trash')->restore(object => $trashed_story);
my $sched = pkg('Schedule')->new(
    action      => 'publish',
    object_id   => $trashed_story->story_id(),
    object_type => 'story',
    repeat      => 'never',
    date        => $now
);
$sched->save();
push @schedules, $sched;
sleep (11 * $scheduler_sleep_interval);

# trashed story now should be published
for my $p ($creator->publish_paths(story => $trashed_story)) {
    ok(-e $p, "story restored from trash has been published");
}

# test expiration
foreach my $story (@stories) {

    my $sched = pkg('Schedule')->new(
        action      => 'expire',
        object_id   => $story->story_id(),
        object_type => 'story',
        repeat      => 'never',
        date        => $now
    );

    $sched->save();
    push @schedules, $sched;

}

# wait to see if it got unpublished.
sleep (10 * $scheduler_sleep_interval);

foreach my $story (@stories) {
    my @paths = $creator->publish_paths(story => $story);

    foreach my $p (@paths) {
        ok(!-e $p, 'story expired');
    }
}

# test archiving
$sched = pkg('Schedule')->new(
    action      => 'retire',
    object_id   => $trashed_story->story_id(),
    object_type => 'story',
    repeat      => 'never',
    date        => $now
);
$sched->save();
push @schedules, $sched;
sleep (11 * $scheduler_sleep_interval);

# story should now be retired
for my $p ($creator->publish_paths(story => $trashed_story)) {
    ok(!-e $p, "previously published story has been retired (removed from website)");
}

($trashed_story) = pkg('Story')->find(story_id => $trashed_story->story_id);
is($trashed_story->retired, 1,
    "previously published story has been retired (still exists in database)");

# test configurable schedule failure
my $story = $creator->create_story();
$story->checkout;
$sched = pkg('Schedule')->new(
    action            => 'publish',
    object_id         => $story->story_id(),
    object_type       => 'story',
    repeat            => 'never',
    date              => $now + 2,             # to leave time for initial is() below!
    failure_max_tries => 2,
    failure_delay_sec => 1,
);
$sched->save();
my $found_sched;
my $cnt = 0;

# the scheduler might block find(), so try 3 times
while (1) {
    last if $cnt++ > 3;
    ($found_sched) = pkg('Schedule')->find(schedule_id => $sched->schedule_id);
    last if $found_sched;
    sleep $scheduler_sleep_interval;
}
is($found_sched->failure_max_tries, 2, "scheduled publish successfully saved with max_tries = 2");

sleep $scheduler_sleep_interval;

undef $found_sched;
$cnt = 0;
while (1) {
    last if $cnt++ > 3;
    ($found_sched) = pkg('Schedule')->find(schedule_id => $sched->schedule_id);
    last if $found_sched;
    sleep $scheduler_sleep_interval;
}
is($found_sched->failure_max_tries, 1,
    "scheduled publish fails due to checked-out story and decrements max_tries to 1");

sleep 2;

($found_sched) = pkg('Schedule')->find(schedule_id => $sched->schedule_id);
is($found_sched, undef, "scheduled publish fails and gives up for good when max_tries = 1");
$story->checkin;
