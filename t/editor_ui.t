# This test attempts to run through a typical editorial session in the
# UI - story creation and publishing.

use strict;
use warnings;

use Krang::Script;
use Krang::Conf qw(KrangRoot RootVirtualHost ApachePort ElementSet);
use LWP::UserAgent;
use HTTP::Request::Common;
use File::Spec::Functions qw(catfile);
use HTTP::Cookies;
use Krang::Category;

# skip tests unless Apache running and we're using TestSet1
BEGIN {
    if (not -e catfile(KrangRoot, 'tmp', 'httpd.pid')) {
        eval "use Test::More skip_all => 'Krang Apache server not running.';";
    } elsif (ElementSet ne 'TestSet1') {
        eval "use Test::More skip_all => 'TestSet1 required.';";
    } else {
        eval "use Test::More qw(no_plan);"
    }
    die $@ if $@;
}
use Krang::Test::Apache;

# get creds
my $username = $ENV{KRANG_USERNAME} ? $ENV{KRANG_USERNAME} : 'admin';
my $password = $ENV{KRANG_PASSWORD} ? $ENV{KRANG_PASSWORD} : 'shredder';

# log in
login_ok($username, $password);

# make sure we have some content
my $undo = catfile(KrangRoot, 'tmp', 'undo.pl');
system("bin/krang_floodfill --stories 5 --sites 1 --cats 3 --media 3 --users 0 --covers 0 --contribs 3 --undo_script $undo > /dev/null 2>&1");
END { system("$undo > /dev/null 2>&1"); }

# make sure that worked
request_ok('story.pl', {rm => 'find'});
response_like(qr/FIND STORY/);
response_unlike(qr/None Found/);

# get the story creation screen
request_ok('story.pl', {rm => 'new_story'});
response_like(qr/NEW STORY/);

# find a category to use
my ($category) = Krang::Category->find(limit      => 1, 
                                       order_by   => 'category_id',
                                       order_desc => 1);

# create a story
my $title = 'title ' . rand();
request_ok('story.pl', 
           { rm          => 'create',
             category_id => $category->category_id,
             type        => 'article',
             title       => $title,
             slug        => 'slug'.rand(),
             cover_date_day   => '1',
             cover_date_month => '1',
             cover_date_year  => '2003',
             cover_date_hour  => '12',
             cover_date_minute=> '00',
             cover_date_ampm  => 'AM',
           });
             
# did it really get created?
my ($story) = Krang::Story->find(limit      => 1,
                                 order_by   => 'story_id', 
                                 order_desc => 1);
is($story->title, $title);

# try publishing it
request_ok('publisher.pl',
           { rm            => 'publish_assets',
             asset_id_list => $story->story_id,
             publish_now   => 1
           });

# did it get published?
($story) = Krang::Story->find(story_id => $story->story_id);
is($story->published_version, $story->version);
ok(-e $story->publish_path());

# delete the story
request_ok('story.pl',
           { rm       => 'delete',
             story_id => $story->story_id });

# did it work?
my $exists = Krang::Story->find(story_id => $story->story_id, count => 1);
ok(!$exists);
