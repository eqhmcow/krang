use Test::More qw(no_plan);
use strict;
use warnings;
use Krang;
use Krang::Category;
use Krang::Site;

BEGIN { use_ok('Krang::Story') }

# creation should fail without required fields
my $story;
eval { $story = Krang::Story->new() };
ok($@);

# create a site and some categories to put stories in
my $site = Krang::Site->new(preview_url  => 'storytest.preview.com',
                            url          => 'storytest.com',
                            publish_path => '/tmp/storytest_publish',
                            preview_path => '/tmp/storytest_preview');
isa_ok($site, 'Krang::Site');
$site->save();
my ($root_cat) = Krang::Category->new(site_id => $site->site_id, dir => "/");
isa_ok($root_cat, 'Krang::Category');
$root_cat->save();

my @cat;
for (0 .. 10) {
    push @cat, Krang::Category->new(site_id   => $site->site_id,
                                    parent_id => $root_cat->category_id,
                                    dir       => 'test_' . time .  '_' . $_);
    isa_ok($root_cat, 'Krang::Category');
    $cat[-1]->save();
}

# cleanup the mess
END {
    $_->delete for @cat;
    $root_cat->delete;
    $site->delete;
}


# create a new story
$story = Krang::Story->new(categories => [$cat[0], $cat[1]],
                           title      => "Test",
                           slug       => "test",
                           class      => "article");
is($story->title, "Test");
is($story->slug, "test");
is($story->class, "article");
is($story->element->name, "article");
my @story_cat = $story->categories();
is(@story_cat, 2);
is($story_cat[0], $cat[0]);
is($story_cat[1], $cat[1]);

# set categories by id
$story->categories($cat[2]->category_id, 
                   $cat[3]->category_id, 
                   $cat[4]->category_id);
@story_cat = $story->categories();
is(@story_cat, 3);
is($story_cat[0]->category_id, $cat[2]->category_id);
is($story_cat[1]->category_id, $cat[3]->category_id);
is($story_cat[2]->category_id, $cat[4]->category_id);

# test category shortcut
is($story->category, $story_cat[0]);

