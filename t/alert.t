use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Alert';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'Schedule';
use Krang::ClassLoader Conf => qw(InstanceElementSet);

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

$ENV{KRANG_TEST_EMAIL} = '' if not $ENV{KRANG_TEST_EMAIL};

# create a site and some categories to put stories in
my $site = pkg('Site')->new(
    preview_url  => 'storytest.preview.com',
    url          => 'storytest.com',
    publish_path => '/tmp/storytest_publish',
    preview_path => '/tmp/storytest_preview'
);
isa_ok($site, 'Krang::Site');
$site->save();
END { $site->delete() }
my ($root_cat) = pkg('Category')->find(site_id => $site->site_id, dir => "/");
isa_ok($root_cat, 'Krang::Category');
$root_cat->save();

my $story;
SKIP: {
    skip('Story tests only work for TestSet1', 1)
      unless (InstanceElementSet eq 'TestSet1');

    # create a new story
    $story = pkg('Story')->new(
        categories => [$root_cat],
        title      => "Test",
        slug       => "test",
        class      => "article"
    );

    $story->save();
    END { $story->delete() if $story }
}

my $alert = pkg('Alert')->new(
    user_id     => $ENV{REMOTE_USER},
    action      => 'checkin',
    category_id => $root_cat->category_id
);

isa_ok($alert, 'Krang::Alert');

$alert->save();

my @alerts = pkg('Alert')->find(alert_id => $alert->alert_id);

is($alerts[0]->alert_id, $alert->alert_id, "Check for return of object from find");

# check object-specific alert functionality
is($alert->object_type, undef, "Check that object_type is NULL by default");
is($alert->object_id,   undef, "Check that object_id is NULL by default");

$alert->{object_type} = 'story';
$alert->{object_id}   = $story->story_id;
eval { $alert->save };
ok(!$@, "Check that alert with object_type/object_id can be saved");
($alert) = pkg('Alert')->find(alert_id => $alert->alert_id);
is($alert->object_type, "story", "Check for return of object_type param from DB");
is($alert->object_id, $story->story_id, "Check for return of object_id param from DB");
my ($count) = pkg('Alert')->find(
    action      => 'checkin',
    object_type => 'story',
    object_id   => $story->story_id,
    count       => 1
);
is($count, 1, "Check that alerts can be found by object_type/object_id");

SKIP: {
    skip('Story tests only work for TestSet1', 1)
      unless (InstanceElementSet eq 'TestSet1');

    $story->checkin();
}

# attempt to trigger alert send by Krang::Schedule->run()
#my $path = File::Spec->catfile($ENV{KRANG_ROOT}, 'logs', "schedule_test.log");
#my $log = IO::File->new(">$path") ||
#  croak("Unable to open logfile: $!");
#Krang::Schedule->run($log);

END { $alert->delete() }
