use strict;
use warnings;

use Krang;
use Krang::Element;
use Krang::Site;

use Test::More qw(no_plan);

BEGIN {
    use_ok('Krang::Category');
}

# need a site id
my $path = File::Spec->catdir($ENV{KRANG_ROOT}, 'sites/test1/publish');
my $site = Krang::Site->new(publish_path => "$path",
                            url => 'test.com');
$site->save();
my $site_id = $site->site_id();

# constructor tests
####################
# make the top level category
my $category = Krang::Category->new(name => '/',
                                    site_id => $site_id);

isa_ok($category, 'Krang::Category');

# invalid arg failure 
eval {my $cat2 = Krang::Category->new(fred => 1)};
is($@ =~ /invalid: 'fred'/, 1, 'new() - invalid arg');

# missing name
eval {my $cat2 = Krang::Category->new(site_id => 1)};
is($@ =~ /'name' not present/, 1, "new() - missing 'name'");

# missing site_id
eval {my $cat2 = Krang::Category->new(name => 1)};
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
my $name = $category->name();
is($name eq '/', 1, 'name()');
is($category->site_id() =~ /^\d+$/, 1, 'site_id');
is($category->url() =~ /$name/, 1, 'url()');

# setter tests
###############
# element()
$element = Krang::Element->new(class => 'category');
$element->save();
$category->element($element);
$category->save();
is($category->element_id(), $element->element_id(), 'element() - setter');

# name()
$category->name('fred');
$category->save();
is($category->url() =~ /fred/, 1, 'name() - setter');

# duplicate test
#################
my $dupe = Krang::Category->new(name => '/fred',
                                site_id => $site_id);
eval {$dupe->save()};
is($@ =~ /duplicate/, 1, 'duplicate_check() - name');

# deletion tests
#################
# add a subcat to make deletion fail
my $subcat = Krang::Category->new(name => 'stuff',
                                  parent_id => $category->category_id(),
                                  site_id => $site_id);
$subcat->save();

# another getter
is($subcat->parent_id() =~ /^\d+$/, 1, 'parent_id()');

# a setter test and test of update_child_url()
$category->name('bob');
$category->save();
my ($sub) = Krang::Category->find(category_id => $subcat->category_id());
is($sub->url() =~ /bob/, 1, 'name() => update_child_url()');

my $success = 0;
eval {$success = $category->delete()};
is($@ =~ /refering/, 1, 'delete() fail');

$success = $subcat->delete();
is($success, 1, 'delete() success');

$success = $category->delete();
is($success, 1, 'delete() success');

# delete site
$success = $site->delete();
is($success, 1, 'site delete()');
