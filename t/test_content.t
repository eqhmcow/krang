use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use File::Path;
use File::Spec::Functions;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(KrangRoot instance InstanceElementSet);
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Media';
use Krang::ClassLoader 'Contrib';
use Krang::ClassLoader 'Story';

BEGIN {

    # use the TestSet1 instance, if there is one
    foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        if (InstanceElementSet eq 'TestSet1') {
            last;
        }
    }

    if (InstanceElementSet eq 'TestSet1') {
        eval 'use Test::More qw(no_plan)';
    } else {
        eval 'use Test::More skip_all=> "Content tests only work for TestSet1"';
    }
}

use_ok(pkg('Test::Content'));

my $creator = pkg('Test::Content')->new;
isa_ok($creator, 'Krang::Test::Content');

can_ok(
    $creator,
    (
        'create_site',             'create_category',
        'create_media',            'create_story',
        'create_user',             'create_contrib',
        'publisher',               'create_template',
        'deploy_test_templates',   'undeploy_test_templates',
        'undeploy_live_templates', 'redeploy_live_templates',
        'get_word',                'delete_item',
        'cleanup'
    )
);

# this is by no means a comprehensive test of get_word()'s randomness.  Just a sanity check.
my %words;
for (1 .. 10) {
    for my $type ('', 'ascii') {
        my $w = $creator->get_word($type);
        ok(!exists($words{$w}), 'get_word()');
        $words{$w} = 1;
    }
}

##################################################
# Krang::Site

my $site;
eval { $site = $creator->create_site(); };

ok($@ && !defined($site), 'create_site()');

$site = $creator->create_site(
    preview_url  => 'preview.fluffydogs.com',
    publish_url  => 'www.fluffydogs.com',
    preview_path => '/tmp/preview_dogs',
    publish_path => '/tmp/publish_dogs'
);

isa_ok($site, 'Krang::Site');

##################################################
# Krang::Category

# don't need any options to create a category.
my $category;
$category = $creator->create_category();

isa_ok($category, 'Krang::Category');

my ($root) = pkg('Category')->find(site_id => $site->site_id);

$category = $creator->create_category(
    dir    => 'poodles',
    parent => $root->category_id,
    data   => 'Fluffy Poodles of the World'
);

isa_ok($category, 'Krang::Category');

##################################################
# Krang::Contrib -- works with no params.
my $contrib;

$contrib = $creator->create_contrib();

isa_ok($contrib, 'Krang::Contrib');

##################################################
# Krang::Media
my $media;

# no longer need category arg.
$media = $creator->create_media();

isa_ok($media, 'Krang::Media');

$media = $creator->create_media(category => $category);

isa_ok($media, 'Krang::Media');

##################################################
# Krang::Story

my $story;

# category not required.
$story = $creator->create_story();

isa_ok($story, 'Krang::Story');

$story = $creator->create_story(category => [$category]);

isa_ok($story, 'Krang::Story');

# further testing to make sure that the story params are supported.
my $story2 = $creator->create_story(
    category => [$root, $category],
    title    => 'title',
    deck     => 'deck',
    header   => 'header',
    pages    => 5
);

is($story2->title, 'title', "create_story() - param('title')");
is($story2->element->child('deck')->data(), 'deck', "create_story() - param('deck')");

my $tmppage = $story2->element->child('page');
is($tmppage->child('header')->data(), 'header', "create_story() - param('header')");

my @pages = $story2->element->match('//page');
is($#pages, 4, "create_story() - param('pages')");

my @story_paths = $creator->publish_paths(story => $story2);
my @story_cats = $story2->categories();

for (my $i = 0 ; $i <= $#story_cats ; $i++) {
    is($story_paths[$i], catfile($story2->publish_path(category => $story_cats[$i]), 'index.html'),
        'publish_paths()');
}

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

is($template->filename, $element->name . '.tmpl', 'create_template(element) check');
is($template->category->category_id(), $root->category_id(), 'create_template(category) check');

# create another template, different category.
$template = $creator->create_template(element => $element, category => $category);

isa_ok($template, 'Krang::Template');
is($template->filename, $element->name . '.tmpl', 'create_template(element) check');
is($template->category->category_id(), $category->category_id(), 'create_template(category) check');

##################################################
# undeploy/deploy of live templates.

my @live_templates = $creator->undeploy_live_templates();
my @live_template_paths;

foreach my $t (@live_templates) {
    my @paths = $publisher->template_search_path(category => $t->category());
    my $p     = $paths[0];
    my $f     = catfile($p, $t->filename());

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
    my $p     = $paths[0];
    my $f     = catfile($p, $t->filename());

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
eval { $creator->delete_item(item => $category); };

ok($@, 'delete_item()');

my $story_id = $story->story_id();

eval { $creator->delete_item(item => $story); };

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
    my ($s) = pkg('Story')->find(story_id => $story_id);
    if (defined($s)) {
        diag("delete_item() did not delete the story -- found by pkg('Story')->find().");
        fail('delete_item()');
    } else {
        pass('delete_item()');
    }
}

##################################################
# create_user()

# this should fail - the admin user should exist.
my $user;

eval { $user = $creator->create_user(login => 'admin'); };

ok($@, 'create_user()');

# create a user with no params

$user = $creator->create_user();
isa_ok($user, 'Krang::User');

# create a user with a few params
$user = $creator->create_user(
    login    => 'testcontentuser',
    password => 'foobar',
    email    => 'foo@bar.com'
);

is($user->login, 'testcontentuser', 'create_user(login)');
ok($user->check_pass('foobar'), 'create_user(password)');
is($user->email, 'foo@bar.com', 'create_user(email)');

##################################################
# cleanup()

my $site_id = $site->site_id;
$cat_id = $category->category_id;

my @story_ids;
my @media_ids;
my @contrib_ids;
my @template_ids;
my @category_ids;
my @user_ids;

for (1 .. 10) {

    my $cat = $creator->create_category(
        dir    => $creator->get_word('ascii'),
        parent => $cat_id,
        data   => join(' ', map { $creator->get_word() } (0 .. 5)),
    );

    my $s = $creator->create_story(category => [$cat]);
    my $m = $creator->create_media(category => $cat);
    my $c = $creator->create_contrib();    # flatten half of them
    my $t =
      $creator->create_template(element => $s->element, category => $cat, flattened => $_ % 2);
    my $u = $creator->create_user();

    push @story_ids,    $s->story_id;
    push @media_ids,    $m->media_id;
    push @contrib_ids,  $c->contrib_id;
    push @template_ids, $t->template_id;
    push @category_ids, $cat->category_id;
    push @user_ids,     $u->user_id;

}

eval { $creator->cleanup(); };

if ($@) {
    diag("cleanup() failed: $@");
    diag("make db may be required to clean things up.");
    fail('cleanup');
} else {
    my ($tmpsite) = pkg('Site')->find(site_id => [$site_id]);
    ok(!defined($tmpsite), 'cleanup() - pkg(Site)');
    my ($tmpcat) = pkg('Category')->find(category_id => [$cat_id]);
    ok(!defined($tmpcat), 'cleanup() - pkg(Category)');

    my @mediafiles = pkg('Media')->find(media_id => \@media_ids);
    is($#mediafiles, -1, 'cleanup() - Krang::Media');

    my @contribfiles = pkg('Contrib')->find(contrib_id => \@contrib_ids);
    is($#contribfiles, -1, 'cleanup() - Krang::Contrib');

    my @storyfiles = pkg('Story')->find(story_id => \@story_ids);
    is($#storyfiles, -1, 'cleanup() - Krang::Story');

    my @tmplfiles = pkg('Template')->find(template_id => \@template_ids);
    is($#tmplfiles, -1, 'cleanup() - Krang::Template');

    my @catfiles = pkg('Category')->find(category_id => \@category_ids);
    is($#catfiles, -1, 'cleanup() - Krang::Category');

    my @users = pkg('User')->find(user_id => \@user_ids);
    is($#users, -1, 'cleanup() - Krang::User');

    # make sure all live templates are where they should be.
    foreach my $f (@live_template_paths) {
        ok(-e $f, "redeploy_live_templates()");
    }

}

END {
    $creator->cleanup();
}
