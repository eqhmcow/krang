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
use Krang::Conf qw(KrangRoot InstanceElementSet);
use Krang::Session;
use Krang::DB qw(dbh);

BEGIN {
    # only start if the schedule daemon is actually running....

    # check for the pid file
    my $pid_file = catfile(KrangRoot, 'tmp', 'schedule_daemon.pid');
    unless (-e $pid_file) {
        eval "use Test::More skip_all => 'Schedule Daemon not running.';";
    } else {
        # get pid
        my $pid = `cat $pid_file`;
        chomp $pid;

        # verify pid is active
        if ($pid) {
            if (InstanceElementSet eq 'TestSet1') {
                eval 'use Test::More qw(no_plan)';
            } else {
                eval 'use Test::More skip_all=>"Schedule tests only work for TestSet1"';
            }
        } else {
            eval "use Test::More skip_all => 'Schedule Daemon not running.';";
        }
    }

    die $@ if $@;

    # set debug flag
    $ENV{SCH_DEBUG} = 1;
    use_ok('Krang::Schedule');
}

our (@non_test_deployed_templates, @test_templates_delete,
     %test_template_lookup, %template_deployed, %template_paths);
our $template_dir = "t/schedule";

my $story_content = <<STORY;
This is my rifle. There are many like it, but this one is mine. My rifle is my best friend. It is my life. I must master it, as I must master my life. Without me my rifle is useless. Without my rifle, I am useless. I must fire my rifle true. I must shoot straighter than my enemy who is trying to kill me. I must shoot him before he shoots me. I will. Before God I swear this creed. My rifle and myself are defenders of my country. We are the masters of our enemy. We are the saviours of my life. So be it ... until there is no enemy ... but peace. Amen.
STORY

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


################################
# story expire and publish test
#

our $publisher = Krang::Publisher->new;

@non_test_deployed_templates = Krang::Template->find(deployed => 1);

foreach (@non_test_deployed_templates) {
    &undeploy_template($_);
}

END {
    # restore system templates.
    foreach (@non_test_deployed_templates) {
        $publisher->deploy_template(template => $_);
    }
}

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

# put test templates out into the production path.
deploy_test_templates($root_cat);

# build story
my $story = Krang::Story->new(categories => [$root_cat],
                              title	 => 'Schedule test story',
                              slug	 => 'slug',
                              class	 => 'article');
my $page = $story->element->child('page');
$page->add_child(class => 'paragraph', data => $story_content);
$story->save;
$story->checkin;

our $s15 = Krang::Schedule->new(object_type => 'story',
                                object_id => $story->story_id,
                                action => 'publish',
                                repeat => 'never',
                                date => $now);
$s15->save;
eval {$count = Krang::Schedule->run};
is($@, '', 'Run did not fail :).');

# wait till the schedule daemon should have run
sleep(7);

test_publish_story($story);


our $s16 = Krang::Schedule->new(object_type => 'story',
                                object_id => $story->story_id,
                                action => 'expire',
                                repeat => 'never',
                                date => $now);
$s16->save;
eval {$count = Krang::Schedule->run};
is($@, '', 'Run did not fail :).');

# wait for another run
sleep(7);

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

END {
    # remove outstanding templates.
    foreach (@test_templates_delete) {
        # delete created templates
        $publisher->undeploy_template(template => $_);
        $_->delete();
    }

    # delete site
    $site->delete();

    # delete schedules
    for (1..14) {
        no strict;
        is(${"s$_"}->delete, 1, "deletion test $_") if ${"s$_"};
    }
}


##### Code basically borrowed from publish.t #####
sub build_publish_paths {
    my $story = shift;
    my @paths;

    for ($story->categories) {
        push @paths,
          catfile($story->publish_path(category => $_), 'index.html');
    }

    return @paths;
}


sub deploy_template {
    my $tmpl = shift;
    my $result;

    my $category = $tmpl->category();

    my @tmpls = $publisher->template_search_path(category => $category);
    my $path = $tmpls[0];

    my $file = catfile($path, $tmpl->filename());

    eval { $result = $publisher->deploy_template(template => $tmpl); };

    if ($@) {
        diag($@);
        fail('deploy_template()');
    }

    return $file;
}


#
# deploy_test_templates() - 
# Places the template files found in t/publish/*.tmpl out on the filesystem
# using Krang::Publisher->deploy_template().
sub deploy_test_templates {
    my ($category) = @_;

    my $template;

    local $/;

    opendir(TEMPLATEDIR, $template_dir) or
      die "ERROR: cannot open dir $template_dir: $!\n";

    my @files = readdir(TEMPLATEDIR);
    closedir(TEMPLATEDIR);

    foreach my $file (@files) {
        next unless ($file =~ s/^(.*)\.tmpl$/$template_dir\/$1\.tmpl/);

        my $element_name = $1;

        open (TMPL, "<$file") or die "ERROR: cannot open file $file: $!\n";
        my $content = <TMPL>;
        close TMPL;

        $template = Krang::Template->new(content => $content,
                                         filename => "$element_name.tmpl",
                                         category => $category);

        eval {$template->save();};

        if ($@) {
            diag("ERROR: $@");
            fail('Krang::Template->new()');
        } else {
            push @test_templates_delete, $template;
            $test_template_lookup{$element_name} = $template;

            $template_paths{$element_name} = &deploy_template($template);

            unless (exists($template_deployed{$element_name})) {
                $template_deployed{$element_name} = $template;
            }
        }
    }

    return;
}


sub load_story_page {
    my $filename = shift;
    my $data;

    local undef $/;

    if (open(PAGE, "<$filename")) {
        $data = <PAGE>;
        close PAGE;
    } else {
        diag("Cannot open $filename: $!");
        fail('Krang::Publisher->publish_story();');
    }

    return $data;
}


sub test_publish_story {
    my $story = shift;

    my @story_paths = build_publish_paths($story);

    for (my $i = $#story_paths; $i >= 0; $i--) {
        my $story_txt = load_story_page($story_paths[$i]);
        $story_txt =~ s/\n//g;
        $story_content =~ s/\n//g;
        if ($story_txt =~ /\w/) {
            ok($story_content eq $story_txt, 'Story page content correct');
            if ($story_content ne $story_txt) {
                diag('Story content does not match expected results');
            }
        } else {
            diag('Missing story content in ' . $story_paths[$i]);
            fail('Krang::Publisher->publish_story() -- compare');
        }
    }
}


# test to make sure that Krang::Template templates are removed from the
# filesystem properly.
sub undeploy_template {

    my $tmpl = shift;

    my $category = $tmpl->category();

    my @tmpls = $publisher->template_search_path(category => $category);
    my $path = $tmpls[0];

    my $file = catfile($path, $tmpl->filename());

    # undeploy template
    eval { $publisher->undeploy_template(template => $tmpl); };

    if ($@) {
        diag($@);
        fail('undeploy_template()');
    }
}
