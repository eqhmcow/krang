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
use Krang::ClassLoader Conf => qw(KrangRoot InstanceElementSet SchedulerMaxChildren);
use Krang::ClassLoader 'Schedule';
use Krang::ClassLoader 'Test::Content';

use Data::Dumper;

my $pidfile;

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

    $pidfile = File::Spec->catfile(KrangRoot, 'tmp', 'schedule_daemon.pid');
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
                diag('Scheduler Daemon Startup failed.  Exiting.');
                exit(1);
            }
        }
        eval 'use Test::More qw(no_plan)';
    } elsif (SchedulerMaxChildren == 0) {
        eval "use Test::More skip_all => 'SchedulerMaxChildren set to 0 -- schedule daemon will not run';";
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

my $preview_url = 'scheduletest.preview.com';
my $publish_url = 'scheduletest.com';
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
for (1..$num_stories) {

    my $story = $creator->create_story();
    push @stories, $story;

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
sleep 10 + $num_stories;

foreach my $story (@stories) {
    my @paths = $creator->publish_paths(story => $story);

    foreach my $p (@paths) {
        ok(-e $p, 'story published');
    }
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

# wait to see if it got published.
sleep 10;

foreach my $story (@stories) {
    my @paths = $creator->publish_paths(story => $story);

    foreach my $p (@paths) {
        ok(!-e $p, 'story expired');
    }
}
