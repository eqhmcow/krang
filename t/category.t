use strict;
use warnings;

use Krang;
use Krang::Element;
use Krang::Site;
use Krang::Template;

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
my $site_id = $site->site_id();


# constructor tests
####################
# make the top level category
my $category = Krang::Category->new(dir => '/',
                                    site_id => $site_id);

isa_ok($category, 'Krang::Category');

# invalid arg failure 
eval {my $cat2 = Krang::Category->new(fred => 1)};
is($@ =~ /invalid: 'fred'/, 1, 'new() - invalid arg');

# missing dir
eval {my $cat2 = Krang::Category->new(site_id => 1)};
is($@ =~ /'dir' not present/, 1, "new() - missing 'dir'");

# missing site_id
eval {my $cat2 = Krang::Category->new(dir => 1)};
is($@ =~ /'site_id' not present/, 1, "new() - missing 'site_id'");


# save test
############
$category->save();
is($category->category_id() =~ /^\d+$/, 1, 'save() test');


# getter tests
########################
is($category->category_id() =~ /^\d+$/, 1, 'category_id()');
my $element = $category->element();
isa_ok($element, 'Krang::Element');
is($category->element_id() =~ /^\d+$/, 1, 'element_id()');
my $dir = $category->dir();
is($dir eq '/', 1, 'dir()');
is($category->site_id() =~ /^\d+$/, 1, 'site_id');
is($category->url() =~ /$dir/, 1, 'url()');


# setter tests
###############
# element()
$element = Krang::Element->new(class => 'category');
$element->save();
$category->element($element);
$category->save();
is($category->element_id(), $element->element_id(), 'element() - setter');

# dir()
my $d = $category->dir('fred');
my $u = $category->url();
$category->save();
$u = $category->url();
is($category->url() =~ /fred/, 1, 'dir() - setter');


# duplicate test
#################
my $dupe = Krang::Category->new(dir => 'fred',
                                site_id => $site_id);
eval {$dupe->save()};
is($@ =~ /duplicate/, 1, 'duplicate_check() - dir');


# find() tests
###############
# setup a bunch of categorys
my $category3 = Krang::Category->new(dir => '/bob3',
                                     site_id => $site_id);
$category3->save();
my $category4 = Krang::Category->new(dir => '/bob4',
                                     site_id => $site_id);
$category4->save();
my $category5 = Krang::Category->new(dir => '/bob5',
                                     site_id => $site_id);
$category5->save();

# we should get an array of 5 objects back
my @categories = Krang::Category->find(url_like => '%.com%',
                                       order_by => 'url',
                                       order_desc => 'asc');
is(scalar @categories, 4, 'find() - quantity');
isa_ok($_, 'Krang::Category') for @categories;
is($categories[0]->url() =~ 'bob3', 1, 'find() - ordering');

# count test
my $count = Krang::Category->find(count => 1,
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

# deletion tests
#################
# add a subcat to make deletion fail
my $subcat = Krang::Category->new(dir => 'stuff',
                                  parent_id => $category->category_id(),
                                  site_id => $site_id);
$subcat->save();

# another getter
is($subcat->parent_id() =~ /^\d+$/, 1, 'parent_id()');

# a setter test and test of update_child_url()
$category->dir('bob');
$category->save();
my ($sub) = Krang::Category->find(category_id => $subcat->category_id());
is($sub->url() =~ /bob/, 1, 'dir() => update_child_url()');

my $success = 0;
my $tmpl = Krang::Template->new(category_id => $category->category_id(),
                                filename => 'bob.tmpl');
$tmpl->save();

$category->dir('freddo');
$category->save();

my ($tmpl2) = Krang::Template->find(template_id => $tmpl->template_id);
is($tmpl2->url() =~ /freddo/, 1, 'update_child_url() - template');

eval {$success = $category->delete()};
is($@ =~ /refers/, 1, 'delete() fail 1');

$success = $subcat->delete();
is($success, 1, 'delete() 1');

eval {$success = $category->delete()};
is($@ =~ /refers/, 1, 'delete() fail 2');

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
