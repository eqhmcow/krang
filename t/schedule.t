use strict;

use Carp qw/verbose croak/;
use Data::Dumper;
use File::Spec::Functions qw(catfile catdir);
use IO::File;
use Storable qw/freeze thaw/;
use Time::Piece;
use Time::Piece::MySQL;
use Time::Seconds;

use Krang::Script;
use Krang::Conf qw(KrangRoot);
use Krang::Session;
use Krang::DB qw(dbh);

BEGIN {
    # only start if the schedule daemon is actually running....
    unless (-e catfile(KrangRoot, 'tmp', 'schedule_daemon.pid')) {
        eval "use Test::More skip_all => 'Schedule Daemon not running.';";
    } else {
        eval "use Test::More qw(no_plan);";
    }

    # set debug flag
    $ENV{SCH_DEBUG} = 1;
    use_ok('Krang::Schedule');
}

my ($date, $next_run);
my $now = localtime;
my $now_mysql = $now->mysql_datetime;
$now_mysql =~ s/:\d+$//;


# I.A
# putative run time for the current week has passed; set next_run to the next
# future runtime in the subsequent week.
#$date = $now - ONE_DAY;
$date = Time::Piece->from_mysql_datetime('2003-03-01 00:00:00');
# 03/01 - is a saturday hence day_of_week - 6
our $s1 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               test_date => $date,
                               day_of_week => 5,
                               hour => $date->hour,
                               minute => $date->minute);
eval {isa_ok($s1->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');
$next_run = Time::Piece->from_mysql_datetime($s1->{next_run});
is($next_run->mysql_datetime, '2003-03-07 00:00:00', 'next_run check 1');


# I.B
# next_run will be set to some time later this week
# run date is two days in the future...
our $s2 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               test_date => $date,
                               day_of_week => 0,
                               hour => $date->hour,
                               minute => $date->min);

eval {isa_ok($s2->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s2->{next_run});
is($next_run->mysql_datetime, '2003-03-02 00:00:00', 'next_run check 2');


# I.C && I.E
# next_run should be set to sometime today, in the future...
our $s3 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               test_date => $date,
                               day_of_week => $date->day_of_week,
                               hour => $date->hour + 2,
                               minute => $date->minute);

eval {isa_ok($s3->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s3->{next_run});
is($next_run->mysql_datetime, '2003-03-01 02:00:00', 'next_run check 3');


# I.C && I.D.i
# advance next_run to next week because the hour on which it was expected to
# run today has already passed
$date = Time::Piece->from_mysql_datetime('2003-03-01 01:00:00');
our $s4 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               test_date => $date,
                               day_of_week => $date->day_of_week,
                               hour => $date->hour - 1,
                               minute => $date->minute);

eval {isa_ok($s4->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s4->{next_run});
is($next_run->mysql_datetime, '2003-03-08 00:00:00', 'next_run check 4');


# I.A && I.D.ii
# next run must be sometime next week less an our hour or more
$date = $now - ONE_DAY - ONE_HOUR;
$date = Time::Piece->from_mysql_datetime('2003-03-01 01:00:00');
our $s5 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               test_date => $date,
                               day_of_week => 5,
                               hour => $date->hour - 1,
                               minute => $date->min);

eval {isa_ok($s5->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s5->{next_run});
is($next_run->mysql_datetime, '2003-03-07 00:00:00', 'next_run check 5');


# I.C && I.F && I.H
# next_run will be set to this week, the present hour ,a few minutes in the
# future
$date = Time::Piece->from_mysql_datetime('2003-03-01 00:00:00');
our $s6 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               test_date => $date,
                               day_of_week => $date->day_of_week,
                               hour => $date->hour,
                               minute => $date->minute + 4);

eval {isa_ok($s6->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s6->{next_run});
is($next_run->mysql_datetime, '2003-03-01 00:04:00', 'next_run check 6');


# I.C && I.F && I.G.i
# next run advances a week because the minute of its putative run has passed
$date = Time::Piece->from_mysql_datetime('2003-03-01 00:01:00');
our $s7 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               test_date => $date,
                               day_of_week => $date->day_of_week,
                               hour => $date->hour,
                               minute => $date->min - 1);

eval {isa_ok($s7->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s7->{next_run});
is($next_run->mysql_datetime, '2003-03-08 00:00:00', 'next_run check 7');


# I.C && I.F && I.G.ii
# next_run is a minute or more in the future
$date = Time::Piece->from_mysql_datetime('2003-03-01 00:00:00');
our $s8 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'weekly',
                               test_date => $date,
                               day_of_week => $date->day_of_week,
                               hour => $date->hour,
                               minute => $date->min + 1);

eval {isa_ok($s8->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s8->{next_run});
is($next_run->mysql_datetime, '2003-03-01 00:01:00', 'next_run check 8');


# II.A && II.D.ii
# next_run is set to tomorrow less a minute or so
$date = Time::Piece->from_mysql_datetime('2003-03-01 01:01:00');
our $s9 = Krang::Schedule->new(action => 'publish',
                               object_id => 1,
                               object_type => 'story',
                               repeat => 'daily',
                               test_date => $date,
                               hour => $date->hour - 1,
                               minute => $date->min - 1);

eval {isa_ok($s9->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s9->{next_run});
is($next_run->mysql_datetime, '2003-03-02 00:00:00', 'next_run check 9');


# II.B
# next_run is an hour or more in the future
$date = Time::Piece->from_mysql_datetime('2003-03-01 00:00:00');
our $s10 = Krang::Schedule->new(action => 'publish',
                                object_id => 1,
                                object_type => 'story',
                                repeat => 'daily',
                                test_date => $date,
                                hour => $date->hour + 1,
                                minute => $date->min);

eval {isa_ok($s10->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s10->{next_run});
is($next_run->mysql_datetime, '2003-03-01 01:00:00', 'next_run check 10');


# II.C && II.D.i
# next_run advances a day as its schedule hour has passed
$date = Time::Piece->from_mysql_datetime('2003-03-01 01:00:00');
our $s11 = Krang::Schedule->new(action => 'publish',
                                object_id => 1,
                                object_type => 'story',
                                repeat => 'daily',
                                test_date => $date,
                                hour => $date->hour - 1,
                                minute => $date->min);

eval {isa_ok($s11->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s11->{next_run});
is($next_run->mysql_datetime, '2003-03-02 00:00:00', 'next_run check 11');


# II.E
# next run is set 1 or more minutes in the future
$date = Time::Piece->from_mysql_datetime('2003-03-01 00:00:00');
our $s12 = Krang::Schedule->new(action => 'publish',
                                object_id => 1,
                                object_type => 'story',
                                repeat => 'daily',
                                test_date => $date,
                                hour => $date->hour,
                                minute => $date->min + 1);

eval {isa_ok($s12->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s12->{next_run});
is($next_run->mysql_datetime, '2003-03-01 00:01:00', 'next_run check 12');


# III.A
# next_run advances an hour because its scheduled minute has passed;
$date = Time::Piece->from_mysql_datetime('2003-03-01 00:01:00');
our $s13 = Krang::Schedule->new(action => 'publish',
                                object_id => 1,
                                object_type => 'story',
                                repeat => 'hourly',
                                test_date => $date,
                                minute => $date->min - 1);

eval {isa_ok($s13->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s13->{next_run});
is($next_run->mysql_datetime, '2003-03-01 01:00:00', 'next_run check 13');


# III.B
# next_run in now...should be run in Krang::Schedule->run
$date = Time::Piece->from_mysql_datetime('2003-03-01 00:00:00');
our $s14 = Krang::Schedule->new(action => 'publish',
                                object_id => 1,
                                object_type => 'story',
                                repeat => 'hourly',
                                test_date => $date,
                                minute => $date->min,
                                context => ['version' => 1]);

eval {isa_ok($s14->save(), 'Krang::Schedule')};
is($@, '', 'save() works :)');

$next_run = Time::Piece->from_mysql_datetime($s14->{next_run});
is($next_run->mysql_datetime, '2003-03-01 00:00:00', 'next_run check 14');

# text 'context' behavior
is(ref $s14->{context}, 'ARRAY', 'context test 1');
my %context1 = @{$s14->{context}};
is($context1{version}, 1, 'context test 2');
is(exists $s14->{_frozen_context}, 1, 'context test 3');
my %context2;
eval {%context2 = @{thaw($s14->{_frozen_context})}};
is($@, '', "context thaw didn't fail");
is($context2{version}, $context1{version}, 'context good');

# run test - 1 tests should run
my $count;
eval {$count = Krang::Schedule->run();};
is($@, '', "run() didn't fail");
is($count >= 14, 1, 'run() succeeded :).');

# force a save failure
$s1->repeat('fred');
eval {$s1->save()};
like($@, qr/'repeat' field set to invalid setting -/, 'save() failure test');


# expire and publish tests
# turn off debugging
is(Krang::Schedule->get_debug, 1, 'debugging on');
Krang::Schedule->set_debug(0);
is(Krang::Schedule->get_debug, 0, 'debugging off');

# build Site
my $pre = catdir KrangRoot, 'tmp', 'story_preview';
my $pub = catdir KrangRoot, 'tmp', 'story_publish';
my $site = Krang::Site->new(preview_url  => 'scheduletest.preview.com',
                            url          => 'scheduletest.com',
                            publish_path => $pub,
                            preview_path => $pre);
$site->save();
my ($root_cat) = Krang::Category->find(site_id => $site->site_id, dir => "/");

# build story
my $story = Krang::Story->new(categories => [$root_cat],
                              title	 => 'Schedule test story',
                              slug	 => 'slug',
                              class	 => 'article');
$story->save;
our $s15 = Krang::Schedule->new(object_type => 'story',
                                object_id => $story->story_id,
                                action => 'publish',
                                repeat => 'never',
                                date => $now);
$s15->save;
eval {$count = Krang::Schedule->run};
is($@, '', 'Run did not fail :).');
is($story->version, 1, 'publish version set');

our $s16 = Krang::Schedule->new(object_type => 'story',
                                object_id => $story->story_id,
                                action => 'expire',
                                repeat => 'never',
                                date => $now);
$s16->save;
eval {$count = Krang::Schedule->run};
is($@, '', 'Run did not fail :).');
my ($obj) = Krang::Story->find(story_id => $story->story_id);
is($obj, undef, 'Story expiration is a success :).');

SKIP: {
    skip "Tmp cleaner tests require touch version 4.5+", 2
      unless `touch --version` =~ /(\d+\.\d+)/ and $1 >= 4.5;

    # clean_tmp tests
    my $path = catfile($ENV{KRANG_ROOT}, 'tmp', 'bob172800x');
    my $path2 = catfile($ENV{KRANG_ROOT}, 'tmp', 'bob3600x');
    if (system("touch -B 172800 $path") == 0 &&
        system("touch -B 3600 $path2") == 0) {
        my @deletions = Krang::Schedule->clean_tmp(max_age => 47);
        my $sof = grep /bob172800x$/, @deletions;
        is($sof >= 1, 1, 'clean_tmp deletion successful');
        is(-e $path2, 1, 'clean_tmp appropriately abstemious');
        unlink $path2;
    }
}


# expire session test

END {
    # delete site
    $site->delete();

    # delete schedules
    for (1..14) {
        no strict;
        is(${"s$_"}->delete, 1, "deletion test $_") if ${"s$_"};
    }
}
