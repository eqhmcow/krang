use strict;
use warnings;
use Krang::Script;

use Krang::Story;
use Krang::Media;

use Krang::Element;
use Krang::Site;
use Krang::Template;
use Storable qw(freeze thaw);
use Krang::Conf qw(ElementSet);

use Test::More qw(no_plan);

BEGIN {
    use_ok('Krang::Category');
}


# need a site id
my $path = File::Spec->catdir($ENV{KRANG_ROOT}, 'sites/test1/publish');
my $path2 = File::Spec->catdir($ENV{KRANG_ROOT}, 'sites/test1/preview');
my $site = Krang::Site->new(preview_path => $path2,
                            preview_url => 'preview.test.com',
                            publish_path => $path,
                            url => 'test.com');
$site->save();
my ($parent) = Krang::Category->find(site_id => $site->site_id);
isa_ok($parent, 'Krang::Category', 'find() parent');


# constructor tests
####################
# make the top level category
my $category = Krang::Category->new(dir => '/blah',
                                    parent_id => $parent->category_id);

isa_ok($category, 'Krang::Category');

# invalid arg failure 
eval {my $cat2 = Krang::Category->new(fred => 1)};
is($@ =~ /invalid: 'fred'/, 1, 'new() - invalid arg');

# missing dir
eval {my $cat2 = Krang::Category->new(site_id => 1)};
is($@ =~ /'dir' not present/, 1, "new() - missing 'dir'");

# missing site_id
eval {my $cat2 = Krang::Category->new(dir => 1)};
is($@ =~ /Either the 'parent_id' or 'site_id' arg/, 1,
   "new() - missing 'site_id'");


# save test
############
$category->save();
is($category->category_id() =~ /^\d+$/, 1, 'save() test');


# getter tests
########################
is($category->category_id() =~ /^\d+$/, 1, 'category_id()');
my $element1 = $category->element();
isa_ok($element1, 'Krang::Element');
is($category->element_id() =~ /^\d+$/, 1, 'element_id()');
my $dir = $category->dir();
is($dir eq '/blah', 1, 'dir()');
is($category->site_id() =~ /^\d+$/, 1, 'site_id');
is($category->url() =~ /$dir/, 1, 'url()');


# setter tests
###############
# element()
my $element = Krang::Element->new(class => 'category', object => $category);
$element->save();
$category->element($element);
$category->save();
is($category->element_id(), $element->element_id(), 'element() - setter');

# delete first element
$element1->delete();

# dir()
my $d = $category->dir('fred');
my $u = $category->url();
$category->save();
my $u2 = $category->url();
is($category->url() =~ /fred/, 1, 'dir() - setter');

# parent_id - must fail
eval {$category->parent_id(100)};
like($@, qr/illegal attempt to set readonly attribute/,
     'parent_id setter test');

# duplicate test
#################
my $dupe = Krang::Category->new(dir => 'fred',
                                parent_id => $parent->category_id);
eval {$dupe->save()};
isa_ok($@, 'Krang::Category::DuplicateURL');
like($@, qr/Duplicate URL/, 'DuplicateURL exception test 1');
like($@->category_id, qr/^\d+$/, 'DuplicateURL exception test 2');

# find() tests
###############
# setup a bunch of categorys
my $category3 = Krang::Category->new(dir => '/bob3',
                                     parent_id => $parent->category_id);
$category3->save();
my $category4 = Krang::Category->new(dir => '/bob4',
                                     parent_id => $parent->category_id);
$category4->save();
my $category5 = Krang::Category->new(dir => '/bob5',
                                     parent_id => $parent->category_id);
$category5->save();

# we should get an array of 5 objects back
my @categories = Krang::Category->find(site_id => $site->site_id,
                                       url_like => '%.com%',
                                       order_by => 'element_id',
                                       order_desc => 1);
is(scalar @categories, 5, 'find() - quantity');
isa_ok($_, 'Krang::Category') for @categories;
is($categories[0]->url() =~ '/bob5', 1, 'find() - ordering');

# count test
my $count = Krang::Category->find(site_id => $site->site_id,
                                  count => 1,
                                  url_like => '%f%');
is($count, 1, 'find() - count');

# ids only
my @category_ids = Krang::Category->find(ids_only => 1,
                                         url_like => '%bob%');
is(scalar @category_ids, 3, 'find() - ids_only');
is($_ =~ /^\d+$/, 1, 'find() - valid ids') for @category_ids;

# category_id
@categories = Krang::Category->find(category_id => [@category_ids]);
is(scalar @categories, 3, 'find() - category_id');
isa_ok($_, 'Krang::Category') for @categories;
is($categories[0]->url() =~ /3/, 1, 'find() - ordering 2');

# limit/offset
@categories = Krang::Category->find(category_id => [@category_ids],
                                    limit => 2,
                                    offset => 1,
                                    order_desc => 'desc');
is(scalar @categories, 2, 'find() - limit/offset 1');
isa_ok($_, 'Krang::Category') for @categories;
is($categories[0]->url() =~ /4/, 1, 'find - limit/offset 2');

# update tests
#################
# add a subcat to make deletion fail
my $subcat = Krang::Category->new(dir => 'stuff',
                                  parent_id => $category->category_id());
$subcat->save();

# test for ancestor ids
####################
my @ancestors = $subcat->ancestors( ids_only => 1);
is( join(' ', @ancestors), $subcat->parent->category_id.' '.$subcat->parent->parent->category_id , 'ancestors test');

# test for ancestor objects
###########################
@ancestors = $subcat->ancestors();
foreach my $ancestor (@ancestors) {
    isa_ok($ancestor, 'Krang::Category');
}

# test for decendant ids
#####################
my @descendants = $parent->descendants(ids_only => 1);
is( join(' ', @descendants), $category->category_id.' '.$category3->category_id.' '.$category4->category_id.' '.$category5->category_id.' '.$subcat->category_id);

# test for decendant objects
############################
@descendants = $parent->descendants();
foreach my $dec (@descendants) {
    isa_ok($dec, 'Krang::Category');
}

# another getter
is($subcat->parent_id() =~ /^\d+$/, 1, 'parent_id()');

# a setter test and test of update_child_url()
$category->dir('bob');
$category->save();
my ($sub) = Krang::Category->find(category_id => $subcat->category_id());
isa_ok($sub, 'Krang::Category');
is($sub->url() =~ /bob/, 1, 'dir() => update_child_urls()');

my $success = 0;
my $tmpl = Krang::Template->new(category_id => $category->category_id(),
                                filename => 'bob.tmpl');
$tmpl->save();

$category->dir('freddo');
$category->save();

my ($tmpl2) = Krang::Template->find(template_id => $tmpl->template_id);
is($tmpl2->url() =~ /freddo/, 1, 'update_child_urls() - template');

# must be able to store and thaw categories with Storable
my $data;
eval { $data = freeze($category) };
ok(not $@);
ok($data);
my $clone;
eval { $clone = thaw($data); };
ok(not $@);
isa_ok($clone, 'Krang::Category');


SKIP: {
    skip('Element tests only work for TestSet1', 1)
      unless (ElementSet eq 'TestSet1');
    test_linked_assets($category);
}

# deletion tests
################
eval {$parent->delete()};
isa_ok($@, 'Krang::Category::RootDeletion');
like($@, qr/Root categories can only be removed by deleting their Site object/,
     'RootDeletion exception test');

eval {$success = $category->delete()};
isa_ok($@, 'Krang::Category::Dependent');
like($@, qr/Category cannot be deleted/, 'delete() fail 1');
my $dependents = $@->dependents;
is($_ =~ /Category|Media|Story|Template/i && $dependents->{$_}->[0] =~ /^\d+$/,
   1, 'Krang::Category::Dependent test')
  for keys %$dependents;

$success = $subcat->delete();
is($success, 1, 'delete() 1');

eval {$success = $category->delete()};
isa_ok($@, 'Krang::Category::Dependent');
like($@, qr/Category cannot be deleted/, 'delete() fail 2');

$success = $tmpl->delete();
is($success, 1, 'delete() 2');

$success = $category->delete();
is($success, 1, 'delete() 3');

$success = $category3->delete();
is($success, 1, 'delete() 4');

$success = $category4->delete();
is($success, 1, 'delete() 5');

$success = $category5->delete();
is($success, 1, 'delete() 6');

# delete site
$success = $site->delete();
is($success, 1, 'site delete()');


### Permission tests #################
#
{
    my $unique = time();

    # create a new site for testing
    my $ptest_site = Krang::Site->new( url => "$unique.com",
                                       preview_url => "preview.$unique.com",
                                       preview_path => 'preview/path/',
                                       publish_path => 'publish/path/' );
    $ptest_site->save();
    my $ptest_site_id = $ptest_site->site_id();
    my ($ptest_root_cat) = Krang::Category->find(site_id=>$ptest_site_id);

    # Create some descendant categories
    my @ptest_cat_dirs = qw(A1 A2 B1 B2);
    my @ptest_categories = ();
    for (@ptest_cat_dirs) {
        my $parent_id = ( /1/ ) ? $ptest_root_cat->category_id() : $ptest_categories[-1]->category_id() ;
        my $newcat = Krang::Category->new( dir => $_,
                                           parent_id => $parent_id );
        $newcat->save();
        push(@ptest_categories, $newcat);
    }

    # Verify that we have permissions
    my ($tmp) = Krang::Category->find(category_id=>$ptest_categories[-1]->category_id);
    is($tmp->may_see, 1, "Found may_see");
    is($tmp->may_edit, 1, "Found may_edit");

    # Change permissions to "read-only" for one of the branches by editing the Admin group
    my $ptest_cat_id = $ptest_categories[0]->category_id();
    my ($admin_group) = Krang::Group->find(group_id=>1);
    $admin_group->categories($ptest_cat_id => "read-only");
    $admin_group->save();

    # Check permissions for that category
    ($tmp) = Krang::Category->find(category_id=>$ptest_cat_id);
    is($tmp->may_see, 1, "read-only may_see => 1");
    is($tmp->may_edit, 0, "read-only may_edit => 0");

    # Check permissions for descendant of that category
    $ptest_cat_id = $ptest_categories[1]->category_id();
    ($tmp) = Krang::Category->find(category_id=>$ptest_cat_id);
    is($tmp->may_see, 1, "descendant read-only may_see => 1");
    is($tmp->may_edit, 0, "descendant read-only may_edit => 0");

    # Check permissions for sibling
    $ptest_cat_id = $ptest_categories[2]->category_id();
    ($tmp) = Krang::Category->find(category_id=>$ptest_cat_id);
    is($tmp->may_see, 1, "sibling edit may_see => 1");
    is($tmp->may_edit, 1, "sibling edit may_edit => 1");

    # Try to save "read-only" category -- should die
    $ptest_cat_id = $ptest_categories[1]->category_id();
    ($tmp) = Krang::Category->find(category_id=>$ptest_cat_id);
    eval { $tmp->save() };
    isa_ok($@, "Krang::Category::NoEditAccess", "save() on read-only category exception");

    # Try to delete()
    eval { $tmp->delete() };
    isa_ok($@, "Krang::Category::NoEditAccess", "delete() on read-only category exception");

    # Try to add descendant category
    eval { Krang::Category->new( dir => "cheeseypoofs",
                                 parent_id => $ptest_cat_id ) };
    isa_ok($@, "Krang::Category::NoEditAccess", "new() descendant from read-only category exception");

    # Change other branch to "hide"
    $ptest_cat_id = $ptest_categories[2]->category_id();
    $admin_group->categories($ptest_cat_id => "hide");
    $admin_group->save();

    # Check permissions for that category
    ($tmp) = Krang::Category->find(category_id=>$ptest_cat_id);
    is($tmp->may_see, 0, "hide may_see => 0");
    is($tmp->may_edit, 0, "hide may_edit => 0");

    # Get count of all site categories -- should return all (5)
    my $ptest_count = Krang::Category->find(count=>1, site_id=>$ptest_site_id);
    is($ptest_count, 5, "Found all categories by default");

    # Get count with "may_see=>1" -- should return root + one branch (3)
    $ptest_count = Krang::Category->find(may_see=>1, count=>1, site_id=>$ptest_site_id);
    is($ptest_count, 3, "Hide hidden categories");

    # Get count with "may_edit=>1" -- should return just root
    $ptest_count = Krang::Category->find(may_edit=>1, count=>1, site_id=>$ptest_site_id);
    is($ptest_count, 1, "Hide un-editable categories");

    # Get count with "may_edit=>0" -- should return all but root (4)
    $ptest_count = Krang::Category->find(may_edit=>0, count=>1, site_id=>$ptest_site_id);
    is($ptest_count, 4, "Hide editable categories");

    # Delete temp categories
    for (reverse@ptest_categories) {
        $_->delete();
    }

    # Delete site
    $ptest_site->delete();
}






# linked_stories linked_media tests
sub test_linked_assets {
    my $category = shift;

    my @test_stories;
    push @test_stories, Krang::Story->new(class => "article",
                                            title => "title one",
                                            slug => "slug one",
                                            categories => [$category]);
    push @test_stories, Krang::Story->new(class => "article",
                                            title => "title two",
                                            slug => "slug two",
                                            categories => [$category]);
    push @test_stories, Krang::Story->new(class => "article",
                                            title => "title three",
                                            slug => "slug three",
                                            categories => [$category]);

    foreach (@test_stories) {
        $_->save();
        $category->element->add_child(class => 'leadin', data => $_);
    }

    my @linked_stories = $category->linked_stories();
    is_deeply([sort(@test_stories)], [sort(@linked_stories)], 'Krang::Category->linked_stories()');

    foreach (@test_stories) { $_->delete(); }



}


