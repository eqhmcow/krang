use strict;
use warnings;

use File::Path;
use File::Spec::Functions;

use Krang::Script;
use Krang::Conf qw(KrangRoot instance InstanceElementSet);
use Krang::Site;
use Krang::Category;
use Krang::Media;
use Krang::Contrib;
use Krang::Story;


BEGIN {
    if (InstanceElementSet eq 'TestSet1') {
        eval 'use Test::More qw(no_plan)';
    } else {
        eval 'use Test::More skip_all=> "Content tests only work for TestSet1"';
    }
}


use_ok('Krang::Test::Content');

my $creator = new Krang::Test::Content;
isa_ok($creator, 'Krang::Test::Content');

can_ok($creator, ('create_site', 'create_category', 'create_media', 
                  'create_story', 'create_contrib', 'publisher',
                  'create_template', 'deploy_test_templates', 'undeploy_test_templates',
                  'undeploy_live_templates', 'redeploy_live_templates',
                  'get_word', 'delete_item', 'cleanup'));

# this is by no means a comprehensive test of get_word()'s randomness.  Just a sanity check.
my %words;
for (1..10) {
    my $w = $creator->get_word();
    ok(!exists($words{$w}), 'get_word()');
    $words{$w} = 1;
}

##################################################
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

##################################################
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

##################################################
# Krang::Contrib -- works with no params.
my $contrib;

$contrib = $creator->create_contrib();

isa_ok($contrib, 'Krang::Contrib');


##################################################
# Krang::Media
my $media;
eval {
    $media = $creator->create_media();
};

ok($@ && !defined($media), 'create_media()');

$media = $creator->create_media(category => $category);

isa_ok($media, 'Krang::Media');


##################################################
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


##################################################
# Krang::Publisher

my $publisher = $creator->publisher();

isa_ok($publisher, 'Krang::Publisher');


##################################################
# Krang::Template

my $template;
my $element = $story->element();

$template = $creator->create_template(element => $element);

isa_ok($template, 'Krang::Template');

is($template->filename, $element->name . '.tmpl','create_template(element) check');
is($template->category->category_id(), $root->category_id(), 'create_template(category) check');


# create another template, different category.
$template = $creator->create_template(element => $element, category => $category);

isa_ok($template, 'Krang::Template');
is($template->filename, $element->name . '.tmpl','create_template(element) check');
is($template->category->category_id(), $category->category_id(), 'create_template(category) check');

##################################################
# undeploy/deploy of live templates.

my @live_templates = $creator->undeploy_live_templates();
my @live_template_paths;

foreach my $t (@live_templates) {
    my @paths = $publisher->template_search_path(category => $t->category());
    my $p = $paths[0];
    my $f = catfile($p, $t->filename());

    ok(!-e $f, sprintf("undeploy_live_templates('%s')", $t->filename()));

    push @live_template_paths, $f;
}


$creator->redeploy_live_templates();

foreach my $f (@live_template_paths) {
    ok(-e $f, "redeploy_live_templates()");
}


##################################################
# deploy/undeploy test templates.


# deploying/undeploying test templates.
my @test_templates = $creator->deploy_test_templates();

# make sure deployed templates are actually there.
my @template_paths;
foreach my $t (@test_templates) {
    my @paths = $publisher->template_search_path(category => $t->category());
    my $p = $paths[0];
    my $f = catfile($p, $t->filename());

    my $ok = ok(-e $f, sprintf("deploy_test_templates('%s')", $t->filename()));

    diag("Missing file '$f'") unless $ok;

    push @template_paths, $f;
}

# undeploy test templates.
$creator->undeploy_test_templates();

foreach my $f (@template_paths) {
    ok(!-e $f, 'undeploy_test_templates()');
}



##################################################
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



##################################################
# cleanup()

my $site_id = $site->site_id;
$cat_id  = $category->category_id;

my @story_ids;
my @media_ids;
my @contrib_ids;
my @template_ids;
my @category_ids;

for (1..10) {

    my $cat = $creator->create_category(
                                        dir    => $creator->get_word(),
                                        parent => $cat_id,
                                        data   => join(' ', map { $creator->get_word() } (0 .. 5) ),
                                       );

    my $s = $creator->create_story(category => [$cat]);
    my $m = $creator->create_media(category => $cat);
    my $c = $creator->create_contrib();
    my $t = $creator->create_template(element => $s->element, category => $cat);

    push @story_ids, $s->story_id;
    push @media_ids, $m->media_id;
    push @contrib_ids, $c->contrib_id;
    push @template_ids, $t->template_id;
    push @category_ids, $cat->category_id;

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

    my @tmplfiles = Krang::Template->find(template_id => \@template_ids);
    is($#tmplfiles, -1, 'cleanup() - Krang::Template');

    my @catfiles = Krang::Category->find(category_id => \@category_ids);
    is($#catfiles, -1, 'cleanup() - Krang::Category');

    # make sure all live templates are where they should be.
    foreach my $f (@live_template_paths) {
        ok(-e $f, "redeploy_live_templates()");
    }

}


END {
    $creator->cleanup();
}
