use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::Script;
use Krang::Alert;
use Krang::Site;
use Krang::Story;
use Krang::Session qw(%session);
use Krang::Schedule;

# create a site and some categories to put stories in
my $site = Krang::Site->new(preview_url  => 'storytest.preview.com',
                            url          => 'storytest.com',
                            publish_path => '/tmp/storytest_publish',
                            preview_path => '/tmp/storytest_preview');
isa_ok($site, 'Krang::Site');
$site->save();
END { $site->delete() }
my ($root_cat) = Krang::Category->find(site_id => $site->site_id, dir => "/");
isa_ok($root_cat, 'Krang::Category');
$root_cat->save();

# create a new story
my $story = Krang::Story->new(categories => [$root_cat],
                           title      => "Test",
                           slug       => "test",
                           class      => "article");

$story->save();
END { $story->delete() }

my $alert = Krang::Alert->new(  user_id => $session{user_id},
                                action => 'checkin',
                                category_id => $root_cat->category_id );

isa_ok($alert, 'Krang::Alert');

$alert->save();

my @alerts = Krang::Alert->find( alert_id => $alert->alert_id );

is($alerts[0]->alert_id, $alert->alert_id, "Check for return of object from find");

# trigger alert
$story->checkin();

# attempt to trigger alert send by Krang::Schedule->run()
my $path = File::Spec->catfile($ENV{KRANG_ROOT}, 'logs', "schedule_test.log");
my $log = IO::File->new(">$path") ||
  croak("Unable to open logfile: $!");
Krang::Schedule->run($log);

END{$alert->delete()}
