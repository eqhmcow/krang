use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;
use Krang::Category;
use Krang::Site;
use Krang::Contrib;
use Krang::Session qw(%session);
use Storable qw(freeze thaw);
use Krang::Conf qw(ElementSet);
use Time::Piece;

BEGIN { use_ok('Krang::Story') }
our $DELETE = 1;


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
END { $site->delete() if $DELETE }
my ($root_cat) = Krang::Category->find(site_id => $site->site_id, dir => "/");
isa_ok($root_cat, 'Krang::Category');
$root_cat->save();

my @cat;
for (0 .. 10) {
    push @cat, Krang::Category->new(site_id   => $site->site_id,
                                    parent_id => $root_cat->category_id,
                                    dir       => 'test_' . $_);
    isa_ok($root_cat, 'Krang::Category');
    $cat[-1]->save();
}

# cleanup the mess
END {
    if ($DELETE) { $_->delete for @cat; }
}

# create new contributor object to test associating with stories
my $contrib = Krang::Contrib->new(prefix => 'Mr', first => 'Matthew', middle => 'Charles', last => 'Vella', email => 'mvella@thepirtgroup.com');
isa_ok($contrib, 'Krang::Contrib');
$contrib->contrib_type_ids(1,3);
$contrib->save();
END { $contrib->delete() if $DELETE; }

# create a new story
$story = Krang::Story->new(categories => [$cat[0], $cat[1]],
                           title      => "Test",
                           slug       => "test",
                           class      => "article");
is($story->title, "Test");
is($story->slug, "test");
is($story->class->display_name, "Article");
is($story->element->name, "article");
my @story_cat = $story->categories();
is(@story_cat, 2);
is($story_cat[0], $cat[0]);
is($story_cat[1], $cat[1]);


SKIP: {
    skip('Element tests only work for TestSet1', 10)
      unless (ElementSet eq 'TestSet1');

    # add some content
    $story->element->child('deck')->data('DECK DECK DECK');
    is($story->element->child('deck')->data(), "DECK DECK DECK");
    my $page = $story->element->child('page');
    isa_ok($page, "Krang::Element");
    is($page->name, $page->class->name);
    is($page->display_name, "Page");
    is($page->children, 2);

    # add five paragraphs
    ok($page->add_child(class => "paragraph", data => "bla1 "x40));
    ok($page->add_child(class => "paragraph", data => "bla2 "x40));
    ok($page->add_child(class => "paragraph", data => "bla3 "x40));
    ok($page->add_child(class => "paragraph", data => "bla4 "x40));
    ok($page->add_child(class => "paragraph", data => "bla5 "x40));
    is($page->children, 7);
};

# test contribs
eval { $story->contribs($contrib); };
like($@, qr/invalid/);
$contrib->selected_contrib_type(1);
$story->contribs($contrib);
is($story->contribs, 1);
is(($story->contribs)[0]->contrib_id, $contrib->contrib_id);

# test schedules
#my @sched = $story->schedules;
#push(@sched, { type   => 'absolute',
#                date   => Time::Piece->new(),
#                action => 'expire' });
#push(@sched, { type    => 'absolute',
#                date    => Time::Piece->new(),
#                action  => 'publish',
#                version => 1,
#              });
#$story->schedules(@sched);
#is_deeply(\@sched, [$story->schedules]);

# test url production
ok($story->url);
is($story->urls, 2);
my $site_url = $cat[0]->site->url;
my $cat_url = $cat[0]->url;
like($story->url, qr/^$cat_url/);
like($story->url, qr/^$site_url/);
like($story->url, qr/^${cat_url}test$/);

# test preview url production
ok($story->preview_url);
is($story->preview_urls, 2);
$site_url = $cat[0]->site->preview_url;
$cat_url = $cat[0]->preview_url;
like($story->preview_url, qr/^$cat_url/);
like($story->preview_url, qr/^$site_url/);
like($story->preview_url, qr/^${cat_url}test$/);

# test preview and publish paths
my $site_path = $cat[0]->site->publish_path;
is($story->publish_path, "$site_path/" . $story->url);
my $site_path2 = $cat[0]->site->preview_path;
is($story->preview_path, "$site_path2/" . $story->preview_url);

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
my @urls = $story->urls;
is(@urls, 3);
$cat_url = $cat[2]->url;
like($urls[0], qr/^$cat_url/);
$cat_url = $cat[3]->url;
like($urls[1], qr/^$cat_url/);
$cat_url = $cat[4]->url;
like($urls[2], qr/^$cat_url/);

# url should change when slug is changed
my $old = $story->url;
$story->slug("foobar");
ok($old ne $story->url);
like($story->url, qr/foobar$/);

# test save
$story->save();
ok($story->story_id);

# cleanup later
END { $story->delete() if $DELETE }

# try loading
my ($story2) = Krang::Story->find(story_id => $story->{story_id});
isa_ok($story2, 'Krang::Story');

# basic fields survived?
for (qw( story_id
         published_version
         class
         checked_out
         checked_out_by
         title
         slug
         notes
         cover_date
         publish_date
         priority )) {
    is($story->$_, $story2->$_, "$_ save/load");
}


SKIP: {
    skip('Element tests only work for TestSet1', 5)
      unless (ElementSet eq 'TestSet1');

    # elements ok?
    is($story2->element->child('deck')->data(), "DECK DECK DECK");
    my $page2 = $story2->element->child('page');
    isa_ok($page2, "Krang::Element");
    is($page2->name, $page2->class->name);
    is($page2->display_name, "Page");
    is($page2->children, 7);
};

# contribs made it?
is($story2->contribs, 1);
is(($story2->contribs)[0]->contrib_id, $contrib->contrib_id);

# schedules?
#is_deeply(\@sched, [$story2->schedules]);

# categories and urls made it
is_deeply([ map { $_->category_id } $story->categories ],
          [ map { $_->category_id } $story2->categories ],
          "category save/load");

is_deeply([$story->urls], [$story2->urls], 'url save/load');

# element load
is($story->element->element_id, $story2->element->element_id);

# try making a copy
my $copy;
eval { $copy = $story->clone() };
ok(not $copy->story_id);

# mangled as expected?
is($copy->title, "Copy of " . $story->title);
is($copy->slug, $story->slug . "_copy");

# basic fields survived?
for (qw( class
         checked_out
         checked_out_by
         notes
         cover_date
         priority )) {
    is($story->$_, $copy->$_, "$_ cloned");
}

# save the copy
$copy->save();
END { $copy->delete if $DELETE };

# make another copy, this should result in a slug ending in _copy2
my $copy2;
eval { $copy2 = $story->clone() };
ok(not $copy2->story_id);

# mangled as expected?
is($copy2->title, "Copy of " . $story->title);
is($copy2->slug, $story->slug . "_copy2");



# checkin/checkout
$story->checkin();
is($story->checked_out, 0);
is($story->checked_out_by, 0);

is($story->checked_out, 0);
is($story->checked_out_by, 0);

eval { $story->save() };
like($@, qr/not checked out/);

$story->checkout();
is($story->checked_out, 1);
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
is($story->checked_out, 1);
is($story->checked_out_by, $ENV{REMOTE_USER});

# test mark_as_published

$story->mark_as_published();

isnt($story->publish_date, undef, 'Krang::Story->mark_as_published()');
is($story->published_version, $story->version(), 'Krang::Story->mark_as_published()');
is($story->checked_out(), 0, 'Krang::Story->mark_as_published()');
is($story->desk_id(), undef, 'Krang::Story->mark_as_published()');




# test serialization
my $data = freeze($story);
ok($data);

my $thawed = thaw($data);
ok($thawed);
isa_ok($thawed, 'Krang::Story');
is($thawed->story_id, $story->story_id);

SKIP: {
    skip('Element tests only work for TestSet1', 1)
      unless (ElementSet eq 'TestSet1');
    
    # test versioning
    my $v = Krang::Story->new(categories => [$cat[0], $cat[1]],
                              title      => "Foo",
                              slug       => "foo",
                              class      => "article");
    END { $v->delete if $v and $DELETE };
    $v->element->child('deck')->data('Version 1 Deck');
    is($v->version, 0);
    $v->save(keep_version => 1);
    is($v->version, 0);
    $v->save();
    
    is($v->version, 1);
    $v->title("Bar");
    
    $v->save();
    is($v->version, 2);
    is($v->title(), "Bar");
    $v->element->child('deck')->data('Version 3 Deck');
    is($v->element->child('deck')->data, 'Version 3 Deck');
    
    $v->revert(1);
    is($v->version, 2);
    is($v->element->child('deck')->data, 'Version 1 Deck');
    
    is($v->title(), "Foo");
    $v->save();
    is($v->version, 3);
    
    $v->revert(2);
    is($v->title(), "Bar");
    $v->save();
    is($v->version, 4);
    
    # try loading old versions
    my ($v1) = Krang::Story->find(story_id => $v->story_id,
                                  version  => 1);
    is($v1->version, 1);
    is($v1->title, "Foo");
};
    

# check that adding a new category can't cause a dup
my $s1 = Krang::Story->new(class => "article",
                           title => "one",
                           slug => "slug",
                           categories => [$cat[0]]);
$s1->save();
ok($s1->story_id);
END { $s1->delete() if $DELETE };

my $s2 = Krang::Story->new(class => "article",
                           title => "one",
                           slug => "slug",
                           categories => [$cat[1]]);
$s2->save();
ok($s2->story_id);
END { $s2->delete() if $DELETE };

eval { $s2->categories($s2->categories, $cat[0]); };
ok($@);
isa_ok($@, 'Krang::Story::DuplicateURL');
                         
# setup three stories to test find
my @find;
push @find, Krang::Story->new(class => "article",
                              title => "title one",
                              slug => "slug one",
                              categories => [$cat[7]]);
push @find, Krang::Story->new(class => "article",
                              title => "title two",
                              slug => "slug two",
                              categories => [$cat[6], $cat[8]]);
$find[-1]->contribs($contrib);
push @find, Krang::Story->new(class => "article",
                              title => "title three",
                              slug => "slug three",
                              categories => [$cat[9]]);
$_->save for @find;
END { if ($DELETE) { $_->delete for @find } };

# find by category
my @result = Krang::Story->find(category_id => $cat[8]->category_id,
                                ids_only => 1);
is(@result, 1);
is($result[0], $find[1]->story_id);

# find by primary category
@result = Krang::Story->find(primary_category_id => $cat[8]->category_id,
                                ids_only => 1);
is(@result, 0);
@result = Krang::Story->find(primary_category_id => $cat[6]->category_id,
                                ids_only => 1);
is(@result, 1);
is($result[0], $find[1]->story_id);

# find by site
@result = Krang::Story->find(site_id => $cat[6]->site_id,
                             ids_only => 1);
ok(@result);
ok((grep { $_ == $find[1]->story_id } @result));

# find by site
@result = Krang::Story->find(primary_site_id => $cat[8]->site_id,
                             ids_only => 1);
ok(@result);
ok((grep { $_ == $find[1]->story_id } @result));

# find by URL
@result = Krang::Story->find(url => $find[1]->url,
                             ids_only => 1);
is(@result, 1);
is($result[0], $find[1]->story_id);

@result = Krang::Story->find(url => $find[1]->url . "XXX",
                             ids_only => 1);
is(@result, 0);

@result = Krang::Story->find(primary_url_like => $find[1]->category->url . '%',
                             ids_only => 1);
is(@result, 1);
is($result[0], $find[1]->story_id);

# find by simple search
@result = Krang::Story->find(simple_search => $find[1]->url,
                             ids_only => 1);
is(@result, 1);
is($result[0], $find[1]->story_id);

@result = Krang::Story->find(simple_search => $find[1]->url . " " . $find[1]->story_id,
                             ids_only => 1);
is(@result, 1);
is($result[0], $find[1]->story_id);

@result = Krang::Story->find(simple_search => $find[1]->url . " " . $find[1]->story_id . " foo",
                             ids_only => 1);
is(@result, 0);

# find by creator search
my ($me) = Krang::User->find(user_id => $ENV{REMOTE_USER});
isa_ok($me, 'Krang::User');

@result = Krang::Story->find(creator_simple => $me->first_name);
ok(grep { $_->story_id == $find[0]->story_id } @result);
ok(grep { $_->story_id == $find[1]->story_id } @result);
ok(grep { $_->story_id == $find[2]->story_id } @result);

@result = Krang::Story->find(creator_simple => $me->first_name . ' ' . $me->last_name);
ok(grep { $_->story_id == $find[0]->story_id } @result);
ok(grep { $_->story_id == $find[1]->story_id } @result);
ok(grep { $_->story_id == $find[2]->story_id } @result);


@result = Krang::Story->find(creator_simple => $me->first_name  . 'foozle');
ok(not grep { $_->story_id == $find[0]->story_id } @result);
ok(not grep { $_->story_id == $find[1]->story_id } @result);
ok(not grep { $_->story_id == $find[2]->story_id } @result);


# count works with simple_search
my $count = Krang::Story->find(simple_search => "",
                               count => 1);
ok($count);


# order_by url working
@result = Krang::Story->find(simple_search => "",
                             order_by => "url");
ok(@result);

# find by contrib_simple
@result = Krang::Story->find(category_id => $cat[8]->category_id,
                             contrib_simple => 'matt', 
                             ids_only => 1);
is(@result, 1);
is($result[0], $find[1]->story_id);


# make sure count is accurate
use Krang::DB qw(dbh);
my ($real_count) = dbh->selectrow_array('SELECT COUNT(*) FROM story');
$count = Krang::Story->find(simple_search => "",
                            count => 1);
is($count, $real_count);

SKIP: {
    skip('Element tests only work for TestSet1', 1)
      unless (ElementSet eq 'TestSet1');

    # create a cover to test links between stories
    my $cover = Krang::Story->new(categories => [$cat[0]],
                                  title      => "Test Cover",
                                  slug       => "test cover",
                                  class      => "cover");
    END { $cover->delete if $cover and $DELETE }
    $cover->element->add_child(class => 'leadin',
                               data  => $find[0]);
    $cover->element->add_child(class => 'leadin',
                               data  => $find[1]);
    $cover->element->add_child(class => 'leadin',
                               data  => $find[2]);
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
    END { $cover2->delete if $cover2 and $DELETE};
};

# test delete by ID
my $doomed = Krang::Story->new(categories => [$cat[0], $cat[1]],
                               title      => "Doomed",
                               slug       => "doomed",
                               class      => "article");
$doomed->save();
my $doomed_id = $doomed->story_id;
my ($obj) = Krang::Story->find(story_id => $doomed_id);
ok($obj);
Krang::Story->delete($doomed_id);
($obj) = Krang::Story->find(story_id => $doomed_id);
ok(not $obj);

# test that when category URL changes, story URL changes too
my $change = Krang::Story->new(class => "article",
                               title => "I can feel it coming",
                               slug => "change",
                               categories => [$cat[0]]);
$change->save();
END { $change->delete if $change and $DELETE };

is($change->url, $cat[0]->url . 'change');

# change the site url
my $url = $site->url;
$url =~ s/test/zest/;
$site->url($url);
like($site->url, qr/zest/);
$site->save();

# did the story URL change?
($change) = Krang::Story->find(story_id => $change->story_id);
is($change->url, 'storyzest.com/test_0/change');



# permissions tests
{
    my $unique = time();

    # create a new site for testing
    my $ptest_site = Krang::Site->new( url          => "$unique.com",
                                       preview_url  => "preview.$unique.com",
                                       preview_path => 'preview/path/',
                                       publish_path => 'publish/path/' );
    $ptest_site->save();
    my $ptest_site_id = $ptest_site->site_id();
    my ($ptest_root_cat) = Krang::Category->find(site_id=>$ptest_site_id);

    my $story = Krang::Story->new(title      => 'Root Cat story', 
                                  categories => [$ptest_root_cat],
                                  slug       => 'rootie',
                                  class => 'article',
                                  cover_date => scalar localtime,
                                 );
    $story->save();
    my @stories = ($story);


    # Create some descendant categories and story
    my @ptest_cat_dirs = qw(A1 A2 B1 B2);
    my @ptest_categories = ();
    for (@ptest_cat_dirs) {
        my $parent_id = ( /1/ ) ? $ptest_root_cat->category_id() : $ptest_categories[-1]->category_id() ;
        my $newcat = Krang::Category->new( dir => $_,
                                           parent_id => $parent_id );
        $newcat->save();
        push(@ptest_categories, $newcat);

        # Add story in this category
        my $story = Krang::Story->new(
                                      title      => $_ .' story', 
                                      categories => [$newcat],
                                      slug       => 'slugo',
                                      class => 'article',
                                      cover_date => scalar localtime,
                                     );
        $story->save();
        push(@stories, $story);
    }


    # Verify that we have permissions
    my ($tmp) = Krang::Story->find(story_id=>$stories[-1]->story_id);
    is($tmp->may_see, 1, "Found may_see");
    is($tmp->may_edit, 1, "Found may_edit");

    # Change group asset_story permissions to "read-only" and check permissions
    my ($admin_group) = Krang::Group->find(group_id=>1);
    $admin_group->asset_story("read-only");
    $admin_group->save();

    ($tmp) = Krang::Story->find(story_id=>$stories[-1]->story_id);
    is($tmp->may_see, 1, "asset_story read-only may_see => 1");
    is($tmp->may_edit, 0, "asset_story read-only may_edit => 0");

    # Change group asset_story permissions to "hide" and check permissions
    $admin_group->asset_story("hide");
    $admin_group->save();

    ($tmp) = Krang::Story->find(story_id=>$stories[-1]->story_id);
    is($tmp->may_see, 1, "asset_story hide may_see => 1");
    is($tmp->may_edit, 0, "asset_story hide may_edit => 0");

    # Reset asset_story to "edit"
    $admin_group->asset_story("edit");
    $admin_group->save();

    # Change permissions to "read-only" for one of the branches by editing the Admin group
    my $ptest_cat_id = $ptest_categories[0]->category_id();
    $admin_group->categories($ptest_cat_id => "read-only");
    $admin_group->save();

    my ($ptest_cat) = Krang::Category->find(category_id => $ptest_categories[0]->category_id());

    # Try to save story to read-only catgory
    $tmp = Krang::Story->new( title => "No story", 
                              categories => [$ptest_cat],
                              class => 'article',
                              slug => 'sluggie',
                              cover_date => scalar localtime);
    eval { $tmp->save() };
    isa_ok($@, "Krang::Story::NoCategoryEditAccess", "save() to read-only category throws exception");

    # Check permissions for that category
    ($tmp) = Krang::Story->find(story_id=>$stories[1]->story_id);
    is($tmp->may_see, 1, "read-only may_see => 1");
    is($tmp->may_edit, 0, "read-only may_edit => 0");

    # Check permissions for descendant of that category
    my $ptest_story_id = $stories[2]->story_id();
    ($tmp) = Krang::Story->find(story_id=>$ptest_story_id);
    is($tmp->may_see, 1, "descendant read-only may_see => 1");
    is($tmp->may_edit, 0, "descendant read-only may_edit => 0");

    # Check permissions for sibling
    $ptest_story_id = $stories[3]->story_id();
    ($tmp) = Krang::Story->find(story_id=>$ptest_story_id);
    is($tmp->may_see, 1, "sibling edit may_see => 1");
    is($tmp->may_edit, 1, "sibling edit may_edit => 1");

    # Try to save "read-only" story -- should die
    $ptest_story_id = $stories[2]->story_id();
    ($tmp) = Krang::Story->find(story_id=>$ptest_story_id);
    eval { $tmp->save() };
    isa_ok($@, "Krang::Story::NoEditAccess", "save() on read-only story exception");

    # Try to delete()
    eval { $tmp->delete() };
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
    ($tmp) = Krang::Story->find(story_id=>$ptest_story_id);
    is($tmp->may_see, 0, "hide may_see => 0");
    is($tmp->may_edit, 0, "hide may_edit => 0");

    # Get count of all story below root category -- should return all (5)
    my $ptest_count = Krang::Story->find(count=>1, below_category_id=>$ptest_root_cat->category_id());
    is($ptest_count, 5, "Found all story by default");

    # Get count with "may_see=>1" -- should return root + one branch (3)
    $ptest_count = Krang::Story->find(may_see=>1, count=>1, below_category_id=>$ptest_root_cat->category_id());
    is($ptest_count, 3, "Hide hidden story");

    # Get count with "may_edit=>1" -- should return just root
    $ptest_count = Krang::Story->find(may_edit=>1, count=>1, below_category_id=>$ptest_root_cat->category_id());
    is($ptest_count, 1, "Hide un-editable story");

    # Delete temp story
    for (reverse @stories) {
        $_->delete();
    }

    # Delete temp categories
    for (reverse@ptest_categories) {
        $_->delete();
    }

    # Delete site
    $ptest_site->delete();
}

