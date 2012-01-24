use Krang::ClassFactory qw(pkg);

# these tests are run from addon_lazy as sub-tests
BEGIN {
    unless ($ENV{SUB_TEST}) {
        eval "use Test::More qw(no_plan);";
        die $@ if $@;
    }
}

use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Contrib';
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'Media';
use Krang::ClassLoader 'Desk';
use File::Spec::Functions;
use Storable qw(freeze thaw);
use Krang::ClassLoader Conf => qw(KrangRoot instance InstanceElementSet);
use Time::Piece;

use Krang::ClassLoader 'Test::Content';

BEGIN { use_ok(pkg('Story')) }
our $DELETE = 1;

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

# use Krang::Test::Content to create sites.
my $creator = pkg('Test::Content')->new;

END {
    $creator->cleanup();
}

my $site = $creator->create_site(
    preview_url  => 'storytest.preview.com',
    publish_url  => 'storytest.com',
    preview_path => '/tmp/storytest_preview',
    publish_path => '/tmp/storytest_publish'
);

isa_ok($site, 'Krang::Site');

# create categories.
my ($root_cat) = pkg('Category')->find(site_id => $site->site_id, dir => "/");

my @cat;
for (0 .. 10) {
    push @cat,
      $creator->create_category(
        dir    => 'test_' . $_,
        parent => $root_cat->category_id
      );
}

# create new contributor object to test associating with stories
my $contrib = $creator->create_contrib(
    prefix => 'Mr',
    first  => 'Matthew',
    middle => 'Charles',
    last   => 'Vella',
    email  => 'mvella@thepirtgroup.com'
);

$contrib->contrib_type_ids(1, 3);
$contrib->save();

# creation should fail without required fields
my $story;
eval { $story = pkg('Story')->new() };
ok($@);

# create a new story
eval {
    $story = pkg('Story')->new(
        categories => [$cat[0], $cat[1]],
        title      => "Test",
        slug       => "test",
        class      => "article"
    );
};

# Was story creation successful?
if ($@) {
    if ($@ =~ qr/Unable to find top-level element named 'article'/) {

        # Story type "article" doesn't exist in this set.  Exit test now.
        $DELETE = 0;
      SKIP: { skip("Unable to find top-level element named 'article' in element lib"); }
        exit(0);
    } else {

        # We've encountered some other unexpected error.  Re-throw.
        die($@);
    }
}

can_ok(
    $story, qw/title slug cover_date class element category categories
      notes version desk_id last_desk_id published_version preview_version
      contribs url preview_url urls preview_urls find save
      checkin checkout checked_out checked_out_by revert
      linked_stories linked_media move_to_desk publish_path preview_path
      delete clone serialize_xml deserialize_xml story_uuid
      retire unretire trash untrash/
);

is($story->title,               "Test");
is($story->slug,                "test");
is($story->class->display_name, "Article");
is($story->element->name,       "article");
like($story->story_uuid, qr/^[0-9A-F]{8}-([0-9A-Z]{4}-){3}[0-9A-F]{12}$/);
my @story_cat = $story->categories();
is(@story_cat,    2);
is($story_cat[0], $cat[0]);
is($story_cat[1], $cat[1]);

# make sure our id_meth and uuid_meth are correct
my $method = $story->id_meth;
is($story->$method, $story->story_id, 'id_meth() is correct');
$method = $story->uuid_meth;
is($story->$method, $story->story_uuid, 'uuid_meth() is correct');

SKIP: {
    skip('Element tests only work for TestSet1', 10)
      unless (InstanceElementSet eq 'TestSet1');

    # add some content
    $story->element->child('deck')->data('DECK DECK DECK');
    is($story->element->child('deck')->data(), "DECK DECK DECK");
    my $page = $story->element->child('page');
    isa_ok($page, "Krang::Element");
    is($page->name,         $page->class->name);
    is($page->display_name, "Page");
    is($page->children,     2);

    # add five paragraphs
    ok($page->add_child(class => "paragraph", data => "bla1 " x 40));
    ok($page->add_child(class => "paragraph", data => "bla2 " x 40));
    ok($page->add_child(class => "paragraph", data => "bla3 " x 40));
    ok($page->add_child(class => "paragraph", data => "bla4 " x 40));
    ok($page->add_child(class => "paragraph", data => "bla5 " x 40));
    is($page->children, 7);
}

# test contribs
$contrib->selected_contrib_type(undef);
eval { $story->contribs($contrib); };
like($@, qr/invalid/);
$contrib->selected_contrib_type(1);
$story->contribs($contrib);
is($story->contribs, 1);
is(($story->contribs)[0]->contrib_id, $contrib->contrib_id);

test_urls($creator);

# test url production
# ok($story->url);
# is($story->urls, 2);
# my $site_url = $cat[0]->site->url;
# my $cat_url = $cat[0]->url;
# like($story->url, qr/^$cat_url/);
# like($story->url, qr/^$site_url/);
# like($story->url, qr/^${cat_url}test$/);

# # test preview url production
# ok($story->preview_url);
# is($story->preview_urls, 2);
# $site_url = $cat[0]->site->preview_url;
# $cat_url = $cat[0]->preview_url;
# like($story->preview_url, qr/^$cat_url/);
# like($story->preview_url, qr/^$site_url/);
# like($story->preview_url, qr/^${cat_url}test$/);

# test preview and publish paths
is($story->publish_path, "/tmp/storytest_publish/test_0/test");
is($story->preview_path, "/tmp/storytest_preview/test_0/test");

# set categories by id
$story->categories($cat[2]->category_id, $cat[3]->category_id, $cat[4]->category_id);
@story_cat = $story->categories();
is(@story_cat,                 3);
is($story_cat[0]->category_id, $cat[2]->category_id);
is($story_cat[1]->category_id, $cat[3]->category_id);
is($story_cat[2]->category_id, $cat[4]->category_id);

# test category shortcut
my $root_cat_story = pkg('Story')->new(title => "Root Cat Story", slug => "root_cat_story_1", class => 'article',
                                       categories => [ $root_cat ]);
$root_cat_story->save();
is($story->category, $story_cat[0]);
is($story->category(dir_only => 1), $story_cat[0]->dir,
   "Krang::Story->category(dir_only => 1)");
is($story->category(level => 1)->category_id, $story_cat[0]->category_id,
   "Krang::Story->category(level => 1)");
is($story->category(level => 0)->category_id, $root_cat->category_id,
   "Krang::Story->category(level => 0)");
is($story->category(level => 1, dir_only => 1), $story_cat[0]->dir,
   "Krang::Story->category(level => 1, dir_only => 1)");
is($story->category(level => 0, dir_only => 1), $root_cat->dir,
   "Krang::Story->category(level => 0, dir_only => 1)");
is($story->category(level => 2), undef,
   "Krang::Story->category(level => 2) - (unexisting category)");
is($story->category(level => 2, dir_only => 1), '',
   "Krang::Story->category(level => 2, dir_only => 1) - (unexisting category)");
is($story->category(depth_only => 1), 1,
   "Krang::Story->category(depth_only => 1)");
is($root_cat_story->category(depth_only => 1), 0,
   "Krang::Story->category(depth_only => 0)");
$root_cat_story->delete();

# test urls
my @urls = $story->urls;
is(@urls, 3);
my $cat_url = $cat[2]->url;
like($urls[0], qr/^$cat_url/);
$cat_url = $cat[3]->url;
like($urls[1], qr/^$cat_url/);
$cat_url = $cat[4]->url;
like($urls[2], qr/^$cat_url/);

# url should change when slug is changed
my $old = $story->url;
$story->slug("foobar");
ok($old ne $story->url);
like($story->url, qr/foobar\/$/);

# test save
$story->save();
ok($story->story_id);

# cleanup later
END { $story->delete() if $DELETE }

# try loading
my ($story2) = pkg('Story')->find(story_id => $story->{story_id});
isa_ok($story2, 'Krang::Story');

# basic fields survived?
for (
    qw( story_id
    story_uuid
    published_version
    preview_version
    class
    checked_out
    checked_out_by
    title
    slug
    notes
    cover_date
    publish_date
    retired
    trashed )
  )
{
    is($story->$_, $story2->$_, "$_ save/load");
}

# try loading by UUID
my ($story_by_uuid) = pkg('Story')->find(story_uuid => $story->{story_uuid});
isa_ok($story_by_uuid, 'Krang::Story');
is($story_by_uuid->story_id, $story->story_id);

# test hidden
test_hidden($root_cat);

SKIP: {
    skip('Element tests only work for TestSet1', 5)
      unless (InstanceElementSet eq 'TestSet1');

    # elements ok?
    is($story2->element->child('deck')->data(), "DECK DECK DECK");
    my $page2 = $story2->element->child('page');
    isa_ok($page2, "Krang::Element");
    is($page2->name,         $page2->class->name);
    is($page2->display_name, "Page");
    is($page2->children,     7);
}

# contribs made it?
is($story2->contribs, 1);
is(($story2->contribs)[0]->contrib_id, $contrib->contrib_id);

# schedules?
#is_deeply(\@sched, [$story2->schedules]);

# categories and urls made it
is_deeply(
    [map { $_->category_id } $story->categories],
    [map { $_->category_id } $story2->categories],
    "category save/load"
);

is_deeply([$story->urls], [$story2->urls], 'url save/load');

# element load
is($story->element->element_id, $story2->element->element_id);

# try making a copy
my $copy;
eval { $copy = $story->clone() };
ok(not $copy->story_id);
ok($copy->story_uuid ne $story->story_uuid);

# mangled as expected?
is($copy->title, "Copy of " . $story->title);
is($copy->slug,  $story->slug . "_copy");

# basic fields survived?
for (
    qw( class
    checked_out
    checked_out_by
    notes
    cover_date
    retired
    trashed )
  )
{
    is($story->$_, $copy->$_, "$_ cloned");
}

# save the copy
$copy->save();
END { $copy->delete if $DELETE }

# make another copy, this should result in a slug ending in _copy2
my $copy2;
eval { $copy2 = $story->clone() };
ok(not $copy2->story_id);
ok($copy2->story_uuid ne $story->story_uuid);

# mangled as expected?
is($copy2->title, "Copy of " . $story->title);
is($copy2->slug,  $story->slug . "_copy2");

# checkin/checkout
$story->checkin();
is($story->checked_out,    0);
is($story->checked_out_by, 0);

is($story->checked_out,    0);
is($story->checked_out_by, 0);

eval { $story->save() };
like($@, qr/not checked out/);

$story->checkout();
is($story->checked_out,    1);
is($story->checked_out_by, $ENV{REMOTE_USER});

# become someone else and try to checkout the story
{
    my $new_user_id = $ENV{REMOTE_USER} + 1;
    local $ENV{REMOTE_USER} = $new_user_id;

    eval { $story->checkout };
    like($@, qr/already checked out/);
    eval { $story->save() };
    like($@, qr/checked out/);
}
is($story->checked_out,    1);
is($story->checked_out_by, $ENV{REMOTE_USER});

# test mark_as_published

$story->mark_as_published();

isnt($story->publish_date, undef, 'Krang::Story->mark_as_published()');
is($story->published_version, $story->version(), 'Krang::Story->mark_as_published()');
is($story->checked_out(),     0,                 'Krang::Story->mark_as_published()');
is($story->desk_id(),         undef,             'Krang::Story->mark_as_published()');

# test mark_as_previewed
$story->checkout();

$story->mark_as_previewed();
is($story->preview_version, $story->version(), 'Krang::Story->mark_as_previewed()');

# check with unsaved content.
$story->mark_as_previewed(unsaved => 1);
is($story->preview_version, -1, 'Krang::Story->mark_as_previewed()');

# test serialization
my $data = freeze($story);
ok($data);

my $thawed = thaw($data);
ok($thawed);
isa_ok($thawed, 'Krang::Story');
is($thawed->story_id,   $story->story_id);
is($thawed->story_uuid, $story->story_uuid);

SKIP: {
    skip('Element tests only work for TestSet1', 1)
      unless (InstanceElementSet eq 'TestSet1');

    # test versioning
    my $v = pkg('Story')->new(
        categories => [$cat[0], $cat[1]],
        title      => "Foo",
        slug       => "foo",
        class      => "article"
    );
    END { $v->delete if $v and $DELETE }
    $v->element->child('deck')->data('Version 1 Deck');
    is($v->version, 0);
    $v->save(keep_version => 1);
    is($v->version, 0);
    $v->save();

    is($v->version, 1);
    $v->title("Bar");

    $v->save();
    is($v->version, 2, 'Is version 2');
    is($v->title(), "Bar", 'Title eq "Bar"');
    $v->element->child('deck')->data('Version 3 Deck');
    is($v->element->child('deck')->data, 'Version 3 Deck');

    $v->revert(1);
    is($v->version,                      3);
    is($v->element->child('deck')->data, 'Version 1 Deck');
    is($v->title(),                      "Foo");

    $v->revert(2);
    is($v->title(), "Bar");
    is($v->version, 4);

    # try loading old versions
    my ($v1) = pkg('Story')->find(
        story_id => $v->story_id,
        version  => 1
    );
    is($v1->version,           1);
    is($v1->title,             "Foo");
    is($v1->checked_out,       0);
    is($v1->checked_out_by,    0);
    is($v1->published_version, 0);

    # try pruning old versions
    my @all_versions = @{$v->all_versions};
    is(@all_versions, 5);
    $v->prune_versions(number_to_keep => 2);
    @all_versions = @{$v->all_versions};
    is(@all_versions,    2);
    is($all_versions[0], 3);
    is($all_versions[1], 4);
}

# test for bug involving reverting after deleting an element
SKIP: {
    skip('Element tests only work for TestSet1', 1)
      unless (InstanceElementSet eq 'TestSet1');

    # test versioning
    my $v = pkg('Story')->new(
        categories => [$cat[0], $cat[1]],
        title      => "Foo",
        slug       => "foo2",
        class      => "article"
    );
    END { $v->delete if $v and $DELETE }
    $v->element->child('deck')->data('Version 1 Deck');
    is($v->version, 0);

    my $page = $v->element->child('page');
    my $p = $page->add_child(class => 'paragraph');
    $p->data('Version 1 Paragraph');

    $v->save();
    is($v->version, 1);

    my ($v2) = pkg('Story')->find(story_id => $v->story_id);
    my $page2 = $v2->element->child('page');
    my $p2 = $page2->add_child(class => 'paragraph');
    $p2->data('Version 2 Paragraph');
    $v2->save();
    my @para = $page2->match('paragraph');
    is(scalar(@para), 2);
    is($v2->version, 2);

    # now create version 3, deleting the v1 paragraph
    my ($v3) = pkg('Story')->find(story_id => $v->story_id);
    my $page3 = $v3->element->child('page');
    my ($p3) = $page3->match('paragraph[0]');
    $page3->remove_children($p3);
    @para = $page3->match('paragraph');
    is(scalar(@para), 1);
    $v3->save();
    is($v3->version, 3);

    # load version 3 and revert it to version 2, the bug was that the
    # old paragraph wouldn't get saved although it would get loaded
    my ($old) = pkg('Story')->find(story_id => $v->story_id);
    @para = $old->element->match('//paragraph');
    is(scalar(@para), 1);

    $old->revert(2);
    @para = $old->element->match('//paragraph');
    is(scalar(@para), 2);

    my ($reverted) = pkg('Story')->find(story_id => $v->story_id);

    # this fails when the bug is present - the resurected paragraph
    # didn't successfully make it to the DB
    @para = $reverted->element->match('//paragraph');
    is(scalar(@para), 2);

    $v->delete;
    undef $v;
}

# check that adding a new category can't cause a dup
my $s1 = pkg('Story')->new(
    class      => "article",
    title      => "one",
    slug       => "slug",
    categories => [$cat[0]]
);
$s1->save();
ok($s1->story_id);
END { $s1->delete() if $DELETE }

my $s2 = pkg('Story')->new(
    class      => "article",
    title      => "one",
    slug       => "slug",
    categories => [$cat[1]]
);
$s2->save();
ok($s2->story_id);
END { $s2->delete() if $DELETE }

eval { $s2->categories($s2->categories, $cat[0]); };
ok($@);
isa_ok($@, 'Krang::Story::DuplicateURL');

# check that dup is thrown when new story conflicts with existing category
my $test_cat = pkg('Category')->new(
    dir       => 'wilma',
    parent_id => $cat[0]->category_id
);
$test_cat->save;
eval {
    my $dupe_story = pkg('Story')->new(
        class      => 'article',
        categories => [$cat[0]],
        slug       => 'wilma',
        title      => 'wilma'
    );
};
isa_ok($@, 'Krang::Story::DuplicateURL');
$test_cat->delete;

# setup three stories to test find
my @find;
push @find, pkg('Story')->new(
    class      => "article",
    title      => "title one",
    slug       => "slug one",
    categories => [$cat[7]]
);
$find[-1]->element->child('deck')->data("3 one deek one deek one deek")
  if InstanceElementSet eq 'TestSet1';
$find[-1]->element->child('fancy_keyword')->data(['common', 'one'])
  if InstanceElementSet eq 'TestSet1';

push @find, pkg('Story')->new(
    class      => "article",
    title      => "title two",
    slug       => "slug two",
    categories => [$cat[6], $cat[8]]
);
$find[-1]->element->child('deck')->data("2 two deek two deek two deek")
  if InstanceElementSet eq 'TestSet1';
$find[-1]->element->child('fancy_keyword')->data(['common', 'two'])
  if InstanceElementSet eq 'TestSet1';
$find[-1]->contribs($contrib);
push @find, pkg('Story')->new(
    class      => "article",
    title      => "title three",
    slug       => "slug three",
    categories => [$cat[9]]
);
$find[-1]->element->child('deck')->data("1 three three three")
  if InstanceElementSet eq 'TestSet1';
$find[-1]->element->child('fancy_keyword')->data(['common', 'three'])
  if InstanceElementSet eq 'TestSet1';
$_->save for @find;

END {
    if ($DELETE) { $_->delete for @find }
}

# find by category
my @result = pkg('Story')->find(
    category_id => $cat[8]->category_id,
    ids_only    => 1
);
is(@result, 1);
is($result[0], $find[1]->story_id);

# find by primary category
@result = pkg('Story')->find(
    primary_category_id => $cat[8]->category_id,
    ids_only            => 1
);
is(@result, 0);
@result = pkg('Story')->find(
    primary_category_id => $cat[6]->category_id,
    ids_only            => 1
);
is(@result, 1);
is($result[0], $find[1]->story_id);

# find by site
@result = pkg('Story')->find(
    site_id  => $cat[6]->site_id,
    ids_only => 1
);
ok(@result);
ok((grep { $_ == $find[1]->story_id } @result));

# find by site
@result = pkg('Story')->find(
    primary_site_id => $cat[8]->site_id,
    ids_only        => 1
);
ok(@result);
ok((grep { $_ == $find[1]->story_id } @result));

# find by URL
@result = pkg('Story')->find(
    url      => $find[1]->url,
    ids_only => 1
);
is(@result, 1);
is($result[0], $find[1]->story_id);

@result = pkg('Story')->find(
    url      => $find[1]->url . "XXX",
    ids_only => 1
);
is(@result, 0);

@result = pkg('Story')->find(
    primary_url_like => $find[1]->category->url . '%',
    ids_only         => 1
);
is(@result, 1);
is($result[0], $find[1]->story_id);

# find by simple search
@result = pkg('Story')->find(
    simple_search => $find[1]->url,
    ids_only      => 1
);
is(@result, 1);
is($result[0], $find[1]->story_id);

@result = pkg('Story')->find(
    simple_search => $find[1]->url . " " . $find[1]->story_id,
    ids_only      => 1
);
is(@result, 1);
is($result[0], $find[1]->story_id);

@result = pkg('Story')->find(
    simple_search => $find[1]->url . " " . $find[1]->story_id . " foo",
    ids_only      => 1
);
is(@result, 0);

# find by creator search
my ($me) = pkg('User')->find(user_id => $ENV{REMOTE_USER});
isa_ok($me, 'Krang::User');

@result = pkg('Story')->find(creator_simple => $me->first_name);
ok(grep { $_->story_id == $find[0]->story_id } @result);
ok(grep { $_->story_id == $find[1]->story_id } @result);
ok(grep { $_->story_id == $find[2]->story_id } @result);

@result = pkg('Story')->find(creator_simple => $me->first_name . ' ' . $me->last_name);
ok(grep { $_->story_id == $find[0]->story_id } @result);
ok(grep { $_->story_id == $find[1]->story_id } @result);
ok(grep { $_->story_id == $find[2]->story_id } @result);

@result = pkg('Story')->find(creator_simple => $me->first_name . 'foozle');
ok(not grep { $_->story_id == $find[0]->story_id } @result);
ok(not grep { $_->story_id == $find[1]->story_id } @result);
ok(not grep { $_->story_id == $find[2]->story_id } @result);

# count works with simple_search
my $count = pkg('Story')->find(
    simple_search => "",
    count         => 1
);
ok($count);

# order_by url working
@result = pkg('Story')->find(
    simple_search => "",
    order_by      => "url"
);
ok(@result);

# find by contrib_simple
@result = pkg('Story')->find(
    category_id    => $cat[8]->category_id,
    contrib_simple => 'matt',
    ids_only       => 1
);
is(@result, 1);
is($result[0], $find[1]->story_id);

# find by element_index
SKIP: {
    skip('Element tests only work for TestSet1', 1)
      unless (InstanceElementSet eq 'TestSet1');

    @result = pkg('Story')->find(element_index => [deck => "1 three three three"]);
    is(@result, 1);
    is($result[0]->story_id, $find[2]->story_id);

    @result = pkg('Story')->find(element_index_like => [deck => "%deek%"]);
    is(@result,              2);
    is($result[0]->story_id, $find[0]->story_id);
    is($result[1]->story_id, $find[1]->story_id);

    @result = pkg('Story')->find(
        element_index_like => [deck => "%deek%"],
        order_by           => "ei.value"
    );
    is(@result,              2);
    is($result[1]->story_id, $find[0]->story_id);
    is($result[0]->story_id, $find[1]->story_id);

    @result = pkg('Story')->find(element_index_like => [deck => "%one deek%"]);
    is(@result, 1);
    is($result[0]->story_id, $find[0]->story_id);

    @result = pkg('Story')->find(element_index_like => [deck => "%feck%"]);
    is(@result, 0);

    @result = pkg('Story')->find(element_index => [fancy_keyword => 'common']);
    is(@result, 3);

    @result = pkg('Story')->find(element_index => [fancy_keyword => 'one']);
    is(@result, 1);
    is($result[0]->story_id, $find[0]->story_id);

    @result = pkg('Story')->find(element_index => [fancy_keyword => 'two']);
    is(@result, 1);
    is($result[0]->story_id, $find[1]->story_id);

    @result = pkg('Story')->find(element_index => [fancy_keyword => 'three']);
    is(@result, 1);
    is($result[0]->story_id, $find[2]->story_id);

    # find by full-text search - a one word phrase
    @result = pkg('Story')->find(full_text_string => 'two');
    is(@result, 1);

    # find by full-text search - two one-word phrases
    @result = pkg('Story')->find(full_text_string => 'two 2');
    is(@result, 1);

    # find by full-text search - a two-word phrase that doesn't exist
    @result = pkg('Story')->find(full_text_string => '"two 2"');
    is(@result, 0);

    # find by full-text search - a two-word phrase that does exist
    @result = pkg('Story')->find(full_text_string => '"2 two"');
    is(@result, 1);

}

# make sure count is accurate
use Krang::ClassLoader DB => qw(dbh);
my ($real_count) = dbh->selectrow_array('SELECT COUNT(*) FROM story');
$count = pkg('Story')->find(
    simple_search => "",
    count         => 1
);
is($count, $real_count);

SKIP: {
    skip('Element tests only work for TestSet1', 1)
      unless (InstanceElementSet eq 'TestSet1');

    # create a cover to test links between stories
    my $cover = pkg('Story')->new(
        categories => [$cat[0]],
        title      => "Test Cover",
        slug       => "test_cover",
        class      => "cover"
    );
    END { $cover->delete if $cover and $DELETE }
    $cover->element->add_child(
        class => 'leadin',
        data  => $find[0]
    );
    $cover->element->add_child(
        class => 'leadin',
        data  => $find[1]
    );
    $cover->element->add_child(
        class => 'leadin',
        data  => $find[2]
    );
    is($cover->element->children, 4);
    $cover->save;

    # test linked stories
    my @linked_stories = $cover->linked_stories;
    is_deeply([sort(@find)], [sort(@linked_stories)]);

    # clone a cover
    my $cover2 = $cover->clone();

    # should have no categories, oh my
    my @copy_cats = $cover2->categories;
    ok(@copy_cats == 0);
    my @copy_cat_ids = @{$cover2->{category_ids}};
    ok(@copy_cat_ids == 0);
    ok(not $cover2->url);
    @copy_cats = $cover2->categories;
    ok(@copy_cats == 0);
    @copy_cat_ids = @{$cover2->{category_ids}};
    ok(@copy_cat_ids == 0);

    # should fail to save as-is
    eval { $cover2->save };
    isa_ok($@, 'Krang::Story::MissingCategory');

    # assign a new category and save should work
    $cover2->categories([$cat[1]]);
    eval { $cover2->save };
    ok(not $@);
    END { $cover2->delete if $cover2 and $DELETE }

    # test linked media
    test_linked_media();

}

# test delete($id)
my $doomed = pkg('Story')->new(
    categories => [$cat[0], $cat[1]],
    title      => "Doomed",
    slug       => "doomed",
    class      => "article"
);
$doomed->save();
my $doomed_id = $doomed->story_id;
my ($obj) = pkg('Story')->find(story_id => $doomed_id);
ok($obj);
pkg('Story')->delete($doomed_id);
($obj) = pkg('Story')->find(story_id => $doomed_id);
ok(not $obj);

# test delete(story_id => $id)
$doomed = pkg('Story')->new(
    categories => [$cat[0], $cat[1]],
    title      => "Doomed",
    slug       => "doomed",
    class      => "article"
);
$doomed->save();
$doomed_id = $doomed->story_id;
($obj) = pkg('Story')->find(story_id => $doomed_id);
ok($obj);
pkg('Story')->delete(story_id => $doomed_id);
($obj) = pkg('Story')->find(story_id => $doomed_id);
ok(not $obj);

# test delete(class => 'publishtest')
my $delete_class_name = 'publishtest';
my @delete_class      = ();
for my $slug (qw(deji we0 jf28 4583)) {
    push @delete_class, pkg('Story')->new(
        categories => [$cat[0], $cat[1]],
        title      => $slug,
        slug       => $slug,
        class      => $delete_class_name,
    );
}

$_->save() for @delete_class;
isa_ok($_, 'Krang::Story') for @delete_class;
pkg('Story')->delete(class => $delete_class_name);
@delete_class = pkg('Story')->find(class => [$delete_class_name]);
is(@delete_class, 0, "Deleting by class (string)");

# test delete(class => [ qw(publishtest cgi_story) ])
my $delete_class_name_1 = 'publishtest';
@delete_class = ();
for my $slug (qw(deji we0 jf28 4583)) {
    push @delete_class, pkg('Story')->new(
        categories => [$cat[0], $cat[1]],
        title      => $slug,
        slug       => $slug,
        class      => $delete_class_name_1,
    );
}

my $delete_class_name_2 = 'cgi_story';
for my $slug (qw(deji_2 we0_2 jf28_2 4583_2)) {
    push @delete_class, pkg('Story')->new(
        categories => [$cat[0], $cat[1]],
        title      => $slug,
        slug       => $slug,
        class      => $delete_class_name,
    );
}

$_->save() for @delete_class;
isa_ok($_, 'Krang::Story') for @delete_class;
pkg('Story')->delete(class => [$delete_class_name_1, $delete_class_name_2]);
@delete_class = pkg('Story')->find(class => [$delete_class_name_1, $delete_class_name_2]);
is(@delete_class, 0, "Deleting by class (arrayref)");

# test that when category URL changes, story URL changes too
my $change = pkg('Story')->new(
    class      => "article",
    title      => "I can feel it coming",
    slug       => "change",
    categories => [$cat[0]]
);
$change->save();
END { $change->delete if $change and $DELETE }

is($change->url, $cat[0]->url . 'change/');

# change the site url
my $url = $site->url;
$url =~ s/test/zest/;
$site->url($url);
like($site->url, qr/zest/);
$site->save();

# did the story URL change?
($change) = pkg('Story')->find(story_id => $change->story_id);
is($change->url, 'storyzest.com/test_0/change/');

# permissions tests
{
    my $unique = time();

    # create a new site for testing
    my $ptest_site = pkg('Site')->new(
        url          => "$unique.com",
        preview_url  => "preview.$unique.com",
        preview_path => 'preview/path/',
        publish_path => 'publish/path/'
    );
    $ptest_site->save();
    my $ptest_site_id = $ptest_site->site_id();
    my ($ptest_root_cat) = pkg('Category')->find(site_id => $ptest_site_id);

    my $story = pkg('Story')->new(
        title      => 'Root Cat story',
        categories => [$ptest_root_cat],
        slug       => 'rootie',
        class      => 'article',
        cover_date => scalar localtime,
    );
    $story->save();
    my @stories = ($story);

    # Create some descendant categories and story
    my @ptest_cat_dirs   = qw(A1 A2 B1 B2);
    my @ptest_categories = ();
    for (@ptest_cat_dirs) {
        my $parent_id =
          (/1/) ? $ptest_root_cat->category_id() : $ptest_categories[-1]->category_id();
        my $newcat = pkg('Category')->new(
            dir       => $_,
            parent_id => $parent_id
        );
        $newcat->save();
        push(@ptest_categories, $newcat);

        # Add story in this category
        my $story = pkg('Story')->new(
            title      => $_ . ' story',
            categories => [$newcat],
            slug       => 'slugo',
            class      => 'article',
            cover_date => scalar localtime,
        );
        $story->save();
        push(@stories, $story);
    }

    # Verify that we have permissions
    my ($tmp) = pkg('Story')->find(story_id => $stories[-1]->story_id);
    is($tmp->may_see,  1, "Found may_see");
    is($tmp->may_edit, 1, "Found may_edit");

    # Unset admin_delete permission and try to delete
    my ($admin_group) = pkg('Group')->find(group_id => 1);
    $admin_group->admin_delete(0);
    $admin_group->save();

    ($tmp) = pkg('Story')->find(story_id => $stories[-1]->story_id);
    eval { $tmp->delete };
    isa_ok($@, "Krang::Story::NoDeleteAccess");

    # Set admin_delete permission again
    $admin_group->admin_delete(1);
    $admin_group->save();

    # Change group asset_story permissions to "read-only" and check permissions
    $admin_group->asset_story("read-only");
    $admin_group->save();

    ($tmp) = pkg('Story')->find(story_id => $stories[-1]->story_id);
    is($tmp->may_see,  1, "asset_story read-only may_see => 1");
    is($tmp->may_edit, 0, "asset_story read-only may_edit => 0");

    # Change group asset_story permissions to "hide" and check permissions
    $admin_group->asset_story("hide");
    $admin_group->save();

    ($tmp) = pkg('Story')->find(story_id => $stories[-1]->story_id);
    is($tmp->may_see,  1, "asset_story hide may_see => 1");
    is($tmp->may_edit, 0, "asset_story hide may_edit => 0");

    # Reset asset_story to "edit"
    $admin_group->asset_story("edit");
    $admin_group->save();

    # Change permissions to "read-only" for one of the branches by editing the Admin group
    my $ptest_cat_id = $ptest_categories[0]->category_id();
    $admin_group->categories($ptest_cat_id => "read-only");
    $admin_group->save();

    my ($ptest_cat) = pkg('Category')->find(category_id => $ptest_categories[0]->category_id());

    # Try to save story to read-only catgory
    $tmp = pkg('Story')->new(
        title      => "No story",
        categories => [$ptest_cat],
        class      => 'article',
        slug       => 'sluggie',
        cover_date => scalar localtime
    );
    eval { $tmp->save() };
    isa_ok(
        $@,
        "Krang::Story::NoCategoryEditAccess",
        "save() to read-only category throws exception"
    );

    # Check permissions for that category
    ($tmp) = pkg('Story')->find(story_id => $stories[1]->story_id);
    is($tmp->may_see,  1, "read-only may_see => 1");
    is($tmp->may_edit, 0, "read-only may_edit => 0");

    # Check permissions for descendant of that category
    my $ptest_story_id = $stories[2]->story_id();
    ($tmp) = pkg('Story')->find(story_id => $ptest_story_id);
    is($tmp->may_see,  1, "descendant read-only may_see => 1");
    is($tmp->may_edit, 0, "descendant read-only may_edit => 0");

    # Check permissions for sibling
    $ptest_story_id = $stories[3]->story_id();
    ($tmp) = pkg('Story')->find(story_id => $ptest_story_id);
    is($tmp->may_see,  1, "sibling edit may_see => 1");
    is($tmp->may_edit, 1, "sibling edit may_edit => 1");

    # Try to save "read-only" story -- should die
    $ptest_story_id = $stories[2]->story_id();
    ($tmp) = pkg('Story')->find(story_id => $ptest_story_id);
    eval { $tmp->save() };
    isa_ok($@, "Krang::Story::NoEditAccess", "save() on read-only story exception");

    # Try to delete()
    eval { $tmp->trash() };
    isa_ok($@, "Krang::Story::NoEditAccess", "delete() on read-only story exception");

    # Try to checkout()
    eval { $tmp->checkout() };
    isa_ok($@, "Krang::Story::NoEditAccess", "checkout() on read-only story exception");

    # Try to checkin()
    eval { $tmp->checkin() };
    isa_ok($@, "Krang::Story::NoEditAccess", "checkin() on read-only story exception");

    # Change other branch to "hide"
    $ptest_cat_id = $ptest_categories[2]->category_id();
    $admin_group->categories($ptest_cat_id => "hide");
    $admin_group->save();

    # Check permissions for that category
    $ptest_story_id = $stories[3]->story_id();
    ($tmp) = pkg('Story')->find(story_id => $ptest_story_id);
    is($tmp->may_see,  0, "hide may_see => 0");
    is($tmp->may_edit, 0, "hide may_edit => 0");

    # Get count of all story below root category -- should return all (5)
    my $ptest_count =
      pkg('Story')->find(count => 1, below_category_id => $ptest_root_cat->category_id());
    is($ptest_count, 5, "Found all story by default");

    # Get count with "may_see=>1" -- should return root + one branch (3)
    $ptest_count =
      pkg('Story')
      ->find(may_see => 1, count => 1, below_category_id => $ptest_root_cat->category_id());
    is($ptest_count, 3, "Hide hidden story");

    # Get count with "may_edit=>1" -- should return just root
    $ptest_count =
      pkg('Story')
      ->find(may_edit => 1, count => 1, below_category_id => $ptest_root_cat->category_id());
    is($ptest_count, 1, "Hide un-editable story");

  SKIP: {
        skip('Element tests only work for TestSet1', 2)
          unless (InstanceElementSet eq 'TestSet1');

        # confirm find by site_id as arrayref works.
        $ptest_count = pkg('Story')->find(site_id => [$site->site_id]);
        is($ptest_count, 12, "find(site_id => [ids])");

        # confirm find by primary_site_id as arrayref works.
        $ptest_count = pkg('Story')->find(primary_site_id => [$site->site_id]);
        is($ptest_count, 12, "find(primary_site_id => [ids])");
    }

    ### test desk permissions (implemented in rXXXX !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    # setup desks
    my $rw_desk   = pkg('Desk')->new(name => 'read_write_desk');
    my $ro_desk   = pkg('Desk')->new(name => 'read_only_desk');
    my $hide_desk = pkg('Desk')->new(name => 'hide_desk');
    my @desks = ($rw_desk, $ro_desk, $hide_desk);

    # setup group with desk permissions
    my $r_group = pkg('Group')->new(
        name  => 'restricted',
        desks => {
            $rw_desk->desk_id   => 'edit',
            $ro_desk->desk_id   => 'read-only',
            $hide_desk->desk_id => 'hide',
        },
    );
    $r_group->save();

    # put a user into this group
    my $r_user = pkg('User')->new(
        login     => 'bob',
        password  => 'bobspass',
        group_ids => [$r_group->group_id],
    );
    $r_user->save();

    # create a story to test desk permissions
    $story = pkg('Story')->new(
        title      => 'Root Cat story',
        categories => [$ptest_root_cat],
        slug       => 'rootie_3',
        class      => 'article',
        cover_date => scalar localtime,
    );
    $story->save();
    $story->checkin();
    push @stories, $story;

    # make sure story is checked in
    is($story->checked_out,    0, 'Story is not checked out');
    is($story->checked_out_by, 0, 'Story is not checked out by anybody');

    {
        my $old_user = $ENV{REMOTE_USER};

        my $user_id = $r_user->user_id;
        local $ENV{REMOTE_USER} = $user_id;

        $story->checkout;
        is($story->checked_out, 1, 'Story checked out');
        is($story->checked_out_by, $user_id, 'Story checked out by restricted user');
        $story->checkin;

        # move story to RW desk and test its permissions there
        is($story->checked_out,    0, 'Restricted user checked in the story');
        is($story->checked_out_by, 0, 'Story is not checked out by anybody else');
        ok(pkg('Group')->may_move_story_to_desk($rw_desk->desk_id),
                "Passed security check: Restricted user may move story TO desk '"
              . $rw_desk->name
              . "'");
        $story->move_to_desk($rw_desk->desk_id);
        is($story->desk_id, $rw_desk->desk_id,
            "After moving, story now lives on desk '" . $rw_desk->name . "'");
        my ($f_story) = pkg('Story')->find(story_id => $story->story_id);
        isa_ok($f_story, 'Krang::Story', 'Story found via story_id');
        is($f_story->may_see, 1,
            "Restricted user may see the story on desk '" . $rw_desk->name . "' (story listing)");
        is($f_story->may_edit, 1,
            "Restricted user may edit the story on '" . $rw_desk->name . "' (story listing)");
        ($f_story) = pkg('Story')->find(desk_id => $rw_desk->desk_id);
        isa_ok($f_story, 'Krang::Story', 'Story found via desk_id');
        is($f_story->may_see, 1,
            "Restricted user may see the story on desk '" . $rw_desk->name . "' (desk listing)");
        is($f_story->may_edit, 1,
            "Restricted user may edit the story '" . $rw_desk->name . "' (desk listing)");

        # move story to RO desk and test its permissions there
        ok(pkg('Group')->may_move_story_from_desk($rw_desk->desk_id),
                "Passed security check: Restricted user may move story FROM desk '"
              . $rw_desk->name
              . "'");
        ok(pkg('Group')->may_move_story_to_desk($ro_desk->desk_id),
                "Passed security check: Restricted user may move story TO desk '"
              . $ro_desk->name
              . "'");
        $story->move_to_desk($ro_desk->desk_id);
        is($story->last_desk_id, $rw_desk->desk_id, "Story was on desk '" . $rw_desk->name . "'");
        is($story->desk_id, $ro_desk->desk_id, "Story is now on desk '" . $ro_desk->name . "'");
        ($f_story) = pkg('Story')->find(story_id => $story->story_id);
        isa_ok($f_story, 'Krang::Story', 'Story found via story_id');
        is($f_story->may_see, 1,
            "Restricted user may see the story on desk '" . $ro_desk->name . "' (story listing)");
        is($f_story->may_edit, 0,
                "Restricted user may not edit the story on desk '"
              . $ro_desk->name
              . "'(story listing)");
        ($f_story) = pkg('Story')->find(desk_id => $ro_desk->desk_id);
        isa_ok($f_story, 'Krang::Story', 'Story found via desk_id');
        is($f_story->may_see, 1,
            "Restricted user may see the story on desk '" . $ro_desk->name . "' (desk listing)");
        is($f_story->may_edit, 0,
                "Restricted user may not edit the story on desk '"
              . $ro_desk->name
              . "' (desk listing)");

        # restricted user shouldn't be able to further move the story
        is(pkg('Group')->may_move_story_from_desk($ro_desk->desk_id), 0,
                "Didn't pass security check: Restricted user may not move story FROM desk '"
              . $ro_desk->name
              . "'");

        # let the system user move the story back to the RW desk
        local $ENV{REMOTE_USER} = $old_user;
        $story->move_to_desk($rw_desk->desk_id);
        is($story->last_desk_id, $ro_desk->desk_id,
            "System user moved the story: It was on desk '" . $ro_desk->name . "'");
        is($story->desk_id, $rw_desk->desk_id, "It is now on desk '" . $rw_desk->name . "'");

        # finally check that restricted user may not move the story to 'hide' desk
        local $ENV{REMOTE_USER} = $user_id;
        is(pkg('Group')->may_move_story_to_desk($hide_desk->desk_id), 0,
                "Didn't pass security check: Restricted user may not move story TO desk '"
              . $hide_desk->name
              . "'");
    }

    # Delete temp story
    for (reverse @stories) {
        $_->delete();
    }

    # Delete temp categories
    for (reverse @ptest_categories) {
        $_->delete();
    }

    # Delete restricted user, group and desks
    $r_user->delete();
    $r_group->delete();
    $_->delete() for @desks;

    # Delete site
    $ptest_site->delete();
}

# test $story->{last_desk_id} functionality introduced in r3790 - r3798
test_story_desk_id_fields();

sub test_story_desk_id_fields {

    my @desks = pkg('Desk')->find;
    my $story = pkg('Story')->new(
        title      => 'Root Cat story',
        categories => [pkg('Category')->find(dir => '/')],
        slug       => 'trari_trara',
        class      => 'article',
        cover_date => scalar localtime,
    );
    is($story->desk_id,      undef, "After creation, story has no desk_id");
    is($story->last_desk_id, undef, "After creation, story has no last_desk_id");

    $story->save;
    $story->checkin;
    is($story->checked_out, 0, 'Story is now checked in');

    # test desk_id and last_desk_id with Krang::Story->move_to_desk()
    for my $desk (@desks) {
        my ($last_desk_id) = ($story->desk_id || undef);
        $story->move_to_desk($desk->desk_id);
        is($story->desk_id, $desk->desk_id,
            "Moved it to desk '" . $desk->name . "' (checking desk_id)");
        is($story->last_desk_id, $last_desk_id,
            "Moved it to desk '" . $desk->name . "' (checking last_desk_id)");
    }

    # test desk_id and last_desk_id with Krang::Story->checkout()
    my $last_desk_id = $story->desk_id;
    $story->checkout;
    is($story->desk_id, undef, 'Checked it out (desk_id is undef)');
    is($story->last_desk_id, $last_desk_id, 'Checked it out (last_desk_id is set)');

    # test it all again
    $last_desk_id = $story->desk_id;
    $story->checkin;
    is($story->checked_out, 0, 'Story is now checked in');
    my $new_desk_id = $desks[0]->desk_id;
    $story->move_to_desk($new_desk_id);
    is($story->desk_id, $new_desk_id,
        "Moved it to desk '" . $desks[0]->name . "' (checking desk_id)");
    is($story->last_desk_id, $last_desk_id,
        "Moved it to desk '" . $desks[0]->name . "' (checking last_desk_id)");
    $last_desk_id = $story->desk_id;
    $story->checkout;
    is($story->desk_id, undef, 'Checked it out (desk_id is undef)');
    is($story->last_desk_id, $last_desk_id, 'Checked it out (last_desk_id is set)');

    $story->delete();
}

sub test_linked_media {

    # create a new story
    my $story = pkg('Story')->new(
        categories => [$cat[0], $cat[1]],
        title      => "Test",
        slug       => "test",
        class      => "article"
    );

    my $media = create_media($cat[0]);
    $story->save();

    my @photos = $story->linked_media();
    ok(@photos == 0, 'Krang::Story->linked_media()');

    my $page = $story->element->child('page');

    $page->add_child(class => "photo", data => $media);

    @photos = $story->linked_media();
    ok(@photos == 1, 'Krang::Story->linked_media()');

    my $contrib = pkg('Contrib')->new(
        prefix => 'Mr',
        first  => 'Joe',
        middle => 'E',
        last   => 'Buttafuoco',
        email  => 'joey@buttafuoco.com'
    );
    $contrib->contrib_type_ids(1, 3);

    my $media2 = create_media($cat[0]);
    $contrib->image($media2);
    $contrib->selected_contrib_type(1);

    $contrib->save();

    $story->contribs($contrib);

    @photos = $story->linked_media();
    ok(@photos == 2, 'Krang::Story->linked_media()');

    foreach (@photos) {
        ok(($_->media_id == $media->media_id) || ($_->media_id == $media2->media_id),
            'Krang::Story->linked_media()');
    }

    END {
        $media->delete()   if $media;
        $media2->delete()  if $media2;
        $contrib->delete() if $contrib;
        $story->delete()   if $story;
    }

}

#
# create a media object - stolen from floodfill.
#
sub create_media {

    my $category = shift;

    # create a random image
    my ($x, $y);
    my $img = Imager->new(
        xsize => $x = (int(rand(300) + 50)),
        ysize => $y = (int(rand(300) + 50)),
        channels => 3,
    );

    # fill with a random color
    $img->box(
        color  => Imager::Color->new(map { int(rand(255)) } 1 .. 3),
        filled => 1
    );

    # draw some boxes and circles
    for (0 .. (int(rand(8)) + 2)) {
        if ((int(rand(2))) == 1) {
            $img->box(
                color => Imager::Color->new(map { int(rand(255)) } 1 .. 3),
                xmin => (int(rand($x - ($x / 2))) + 1),
                ymin => (int(rand($y - ($y / 2))) + 1),
                xmax   => (int(rand($x * 2)) + 1),
                ymax   => (int(rand($y * 2)) + 1),
                filled => 1
            );
        } else {
            $img->circle(
                color => Imager::Color->new(map { int(rand(255)) } 1 .. 3),
                r     => (int(rand(100)) + 1),
                x     => (int(rand($x)) + 1),
                'y'   => (int(rand($y)) + 1)
            );
        }
    }

    # pick a format
    my $format = (qw(jpg png gif))[int(rand(3))];

    $img->write(file => catfile(KrangRoot, "tmp", "tmp.$format"));
    my $fh = IO::File->new(catfile(KrangRoot, "tmp", "tmp.$format"))
      or die "Unable to open tmp/tmp.$format: $!";

    # Pick a type
    my %media_types    = pkg('Pref')->get('media_type');
    my @media_type_ids = keys(%media_types);
    my $media_type_id  = $media_type_ids[int(rand(scalar(@media_type_ids)))];

    # create a media object
    my $media = pkg('Media')->new(
        title         => get_word(),
        filename      => get_word() . ".$format",
        caption       => get_word(),
        filehandle    => $fh,
        category_id   => $category->category_id,
        media_type_id => $media_type_id,
    );
    eval { $media->save };
    if ($@) {
        if (ref($@) and ref($@) eq 'Krang::Media::DuplicateURL') {
            redo;
        } else {
            die $@;
        }
    }
    unlink(catfile(KrangRoot, "tmp", "tmp.$format"));

    $media->checkin();

    return $media;

}

# test URL functionality
sub test_urls {
    my $creator = shift;

    my @sites;
    my @cats;

    # create multiple sites & cats.
    for (1 .. 5) {
        my $site = $creator->create_site(
            preview_url  => $_ . 'storytest.preview.com',
            publish_url  => $_ . 'storytest.com',
            preview_path => '/tmp/storytest_preview' . $_,
            publish_path => '/tmp/storytest_publish' . $_
        );
        my ($cat) = pkg('Category')->find(site_id => $site->site_id, dir => "/");
        push @sites, $site;
        push @cats,  $cat;
    }

    # create a new story
    my $story = pkg('Story')->new(
        categories => \@cats,
        title      => "Test",
        slug       => "test",
        class      => "article"
    );

    # test primary URL
    my $cat_url      = $cats[0]->url;
    my $cat_prev_url = $cats[0]->preview_url;
    ok($story->url         =~ qr/^$cat_url/,      'Krang::Story->url');
    ok($story->preview_url =~ qr/^$cat_prev_url/, 'Krang::Story->preview_url');

    # test urls()
    my @s_urls = $story->urls();
    for (my $i = 0 ; $i <= $#s_urls ; $i++) {
        my $c_url = $cats[$i]->url;
        ok($s_urls[$i] =~ qr/^$c_url/, 'Krang::Story->urls' . $i);
    }

    # test preview_urls()
    my @p_urls = $story->preview_urls();
    for (my $i = 0 ; $i <= $#p_urls ; $i++) {
        my $pre_url = $cats[$i]->preview_url;
        ok($p_urls[$i] =~ qr/^$pre_url/, 'Krang::Story->preview_urls' . $i);
    }

    # cleanup.
    foreach (@sites) {
        $creator->delete_item(item => $_);
    }
}

sub test_hidden {
    my $cat = shift;

  SKIP: {
        skip('Hidden tests only work for TestSet1', 3)
          unless (InstanceElementSet eq 'TestSet1');

        # create a new story
        my $hidden = pkg('Story')->new(
            categories => [$cat],
            title      => "Test Hidden",
            slug       => "testhidden",
            class      => "hidden"
        );
        $hidden->save();

        # make sure it comes back.
        my $id = $hidden->story_id;

        my ($test) = pkg('Story')->find(story_id => $id);

        ok($test->story_id == $hidden->story_id, 'Krang::Story->show_hidden');

        # do a category search - it shouldn't be found
        my @stories = pkg('Story')->find(category_id => $cat->category_id);

        my $not_found = 1;
        foreach my $s (@stories) {
            $not_found = 0 if ($s->story_id == $hidden->story_id);
        }

        ok($not_found, 'Krang::Story->show_hidden');

        # repeat w/ show_hidden argument.
        @stories = pkg('Story')->find(category_id => $cat->category_id, show_hidden => 1);
        my $found = 0;
        foreach my $s (@stories) {
            $found = 1 if ($s->story_id == $hidden->story_id);
        }
        ok($found, 'Krang::Story->show_hidden');

        # cleanup.
        $hidden->delete;
    }

}

# get a random word
sub get_word {
    my $type = shift;
    $creator->get_word($type);
}
