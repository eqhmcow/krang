use strict;
use warnings;

use Test::More qw(no_plan);
use Krang::Script;
use Krang::Site;
use Krang::Category;
use Krang::Media;
use Krang::Contrib;
use Krang::Story;


use_ok('Krang::Test::Content');

my $creator = new Krang::Test::Content;
isa_ok($creator, 'Krang::Test::Content');

can_ok($creator, ('create_site', 'create_category', 'create_media', 
                  'create_story', 'create_contrib', 'get_word', 
                  'delete_item', 'cleanup'));

# this is by no means a comprehensive test of get_word()'s randomness.  Just a sanity check.
my %words;
for (1..10) {
    my $w = $creator->get_word();
    ok(!exists($words{$w}), 'get_word()');
    $words{$w} = 1;
}


# Krang::Site
my $site;
eval {
    $site = $creator->create_site();
};

ok($@ && !defined($site), 'create_site()');

$site = $creator->create_site(preview_url => 'preview.fluffydogs.com',
                              publish_url => 'www.fluffydogs.com',
                              preview_path => '/tmp/preview_dogs',
                              publish_path => '/tmp/publish_dogs');

isa_ok($site, 'Krang::Site');


# Krang::Category
my $category;
eval {
    $category = $creator->create_category();
};

ok($@ && !defined($category), 'create_category()');

my ($root) = Krang::Category->find(site_id => $site->site_id);

$category = $creator->create_category(dir    => 'poodles',
                                      parent => $root->category_id,
                                      data   => 'Fluffy Poodles of the World');

isa_ok($category, 'Krang::Category');


# Krang::Contrib -- works with no params.
my $contrib;

$contrib = $creator->create_contrib();

isa_ok($contrib, 'Krang::Contrib');


# Krang::Media
my $media;
eval {
    $media = $creator->create_media();
};

ok($@ && !defined($media), 'create_media()');

$media = $creator->create_media(category => $category);

isa_ok($media, 'Krang::Media');


# Krang::Story

my $story;
eval {
    $story = $creator->create_story();
};

ok($@ && !defined($story), 'create_story()');

$story = $creator->create_story(category => [$category]);

isa_ok($story, 'Krang::Story');

# further testing to make sure that the story params are supported.
my $story2 = $creator->create_story(category => [$category],
                                    title    => 'title',
                                    deck     => 'deck',
                                    header   => 'header',
                                    pages    => 5);


is($story2->title, 'title', "create_story() - param('title')");
is($story2->element->child('deck')->data(), 'deck', "create_story() - param('deck')");

my $tmppage = $story2->element->child('page');
is($tmppage->child('header')->data(), 'header', "create_story() - param('header')");

my @pages = $story2->element->match('//page');
is($#pages, 4, "create_story() - param('pages')");


# delete_item

# this should fail - there are stories & media under this category.
my $cat_id = $category->category_id;
eval {
    $creator->delete_item(item => $category);
};

ok($@, 'delete_item()');

my $story_id = $story->story_id();

eval {
    $creator->delete_item(item => $story);
};

if ($@) {
    diag("Unexpected Failure: $@");
    fail('delete_item()');
} else {

    # Search the internal hash for the item -- make sure it's gone.
    my $ok = 1;
    foreach my $s (@{$creator->{stack}{story}}) {
        if ($s->isa('Krang::Story')) {
            if ($s->story_id == $story_id) {
                diag('delete_item() did not delete story -- found in stack');
                fail('delete_item()');
                last;
            }
        } else {
            diag("Found non-story object in story stack: " . ref($s));
        }
    }

    # use find() as well.
    my ($s) = Krang::Story->find(story_id => $story_id);
    if (defined($s)) {
        diag("delete_item() did not delete the story -- found by Krang::Story->find().");
        fail('delete_item()');
    } else {
        pass('delete_item()');
    }
}



#
# test cleanup.
#

my $site_id = $site->site_id;
$cat_id  = $category->category_id;
my @story_ids;
my @media_ids;
my @contrib_ids;

for (1..10) {
    my $s = $creator->create_story(category => [$category]);
    my $m = $creator->create_media(category => $category);
    my $c = $creator->create_contrib();

    push @story_ids, $s->story_id;
    push @media_ids, $m->media_id;
    push @contrib_ids, $c->contrib_id;
}

eval {
    $creator->cleanup();
};

if ($@) {
    diag("cleanup() failed: $@");
    diag("make db may be required to clean things up.");
    fail('cleanup');
} else {
    my ($tmpsite) = Krang::Site->find(site_id => [$site_id]);
    ok(!defined($tmpsite), 'cleanup() - Krang::Site');
    my ($tmpcat) = Krang::Category->find(category_id => [$cat_id]);
    ok(!defined($tmpcat), 'cleanup() - Krang::Category');

    my @mediafiles = Krang::Media->find(media_id => \@media_ids);
    is($#mediafiles, -1, 'cleanup() - Krang::Media');

    my @contribfiles = Krang::Contrib->find(contrib_id => \@contrib_ids);
    is($#contribfiles, -1, 'cleanup() - Krang::Contrib');

    my @storyfiles = Krang::Story->find(story_id => \@story_ids);
    is($#storyfiles, -1, 'cleanup() - Krang::Story');

}


END {
    $creator->cleanup();
}
