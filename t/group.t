## Test script for Krang::Group

use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;
use Krang::Category;
use Krang::Desk;
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

BEGIN { use_ok('Krang::Group') }

# create some categories and clean them up when finished
my $undo = catfile(KrangRoot, 'tmp', 'undo.pl');
system("bin/krang_floodfill --stories 0 --sites 1 --cats 3 --templates 0 --media 0 --users 0 --covers 0 --undo_script $undo 2>&1 /dev/null");
END { system("$undo 2>&1 /dev/null"); }

# Variable for our work
my $group = 0;

# Create a new group object w/o params
eval { $group = Krang::Group->new() };
ok(not ($@), 'Create a new group object w/o params');
die ($@) if ($@);
ok(ref($group), 'Create a new group object w/o params');
isa_ok($group, "Krang::Group");


# Verify that new group has inherited existing root categories and set them to "edit" by default
my @root_cats = Krang::Category->find(ids_only=>1, parent_id=>undef);
my $group_categories = $group->categories();
foreach my $cat (@root_cats) {
    is($group_categories->{$cat}, "edit", "Root category '$cat' defaults to 'edit'");
}


# Verify that new group has inherited existing desks and set them to "edit" by default
my @all_desks = Krang::Desk->find(ids_only=>1);
my $group_desks = $group->desks();
foreach my $desk (@all_desks) {
    is($group_desks->{$desk}, "edit", "Desk '$desk' defaults to 'edit'");
}


# Create a new group object with params
my %test_params = ( name => 'Car Editors',
                    categories          => { 1 => 'read-only', 
                                             2 => 'edit', 
                                             23 => 'hide' },
                    desks               => { },
                    may_publish         => 1,
                    admin_users         => 1,
                    admin_users_limited => 1,
                    admin_groups        => 1,
                    admin_contribs      => 1,
                    admin_sites         => 1,
                    admin_categories    => 1,
                    admin_jobs          => 1,
                    admin_desks         => 1,
                    asset_story         => 'edit',
                    asset_media         => 'read-only',
                    asset_template      => 'hide' );

$group = 0;
eval { $group = Krang::Group->new(%test_params) };
ok(not ($@), 'Create a new group object with params');
die ($@) if ($@);
ok(ref($group), 'Create a new group object with params');
isa_ok($group, "Krang::Group");


# Test invalid create param
eval { Krang::Group->new(%test_params, no_such_param => 1) };
like($@, qr(Can't locate object method "no_such_param" via package "Krang::Group"), 'Test invalid create param');


# Test scalar methods
my @scalar_params = qw( name
                        may_publish
                        admin_users
                        admin_users_limited
                        admin_groups
                        admin_contribs
                        admin_sites
                        admin_categories
                        admin_jobs
                        admin_desks
                        asset_story
                        asset_media
                        asset_template );

for (@scalar_params) {
    my $val = "Test $_";
    ok($group->$_($val), "Set $_");
    is($group->$_(), $val, "Get $_");
}

# Test hash methods
my @hash_params = qw( categories
                      desks );

for (@hash_params) {
    my $val = "Test $_";
    ok($group->$_({$val => "true"}), "Set $_ => 'true'");
    is($group->$_($val), "true", "Get $_");
}


# Test find() for invalid arg handling
eval { Krang::Group->find( no_such_find_arg => 1) };
like($@, qr(Invalid find arg), 'Test invalid find arg');


# Test find(count=>1)
my $count = Krang::Group->find(count=>1);
ok(($count =~ /^\d+$/), "Test find(count=>1)");


# Test find(ids_only=>1)
my @group_ids = ( Krang::Group->find(ids_only=>1) );
is(scalar(@group_ids), $count, "find(ids_only=>1)");
like($group_ids[0], qr(^\d+$), "ids_only really returns IDs");


# Test find(group_ids=>[])
eval { Krang::Group->find(group_ids=>'bad input') };
like($@, qr(group_ids must be an array ref), 'Test bad scalar input to group_ids');

eval { Krang::Group->find(group_ids=>[1, 2, 3, '4bad input']) };
like($@, qr(group_ids array ref may only contain numeric IDs), 'Test bad array ref input to group_ids');

my $count_group_ids = Krang::Group->find(count=>1, group_ids=>[1, 2, 505]);
is($count_group_ids, 2, "Test find(group_ids=>[])");


# Test find(group_id=>1)
eval { ($group) = Krang::Group->find(group_id=>1) };
is($group->group_id, "1", "Test find(group_id=>1)");


# Test save
my $unique_group_name = "Test ". time();
$group = Krang::Group->new();
$group->name($unique_group_name);
eval { $group->save(); };
ok(not($@), "Save without die");
die ($@) if ($@);
ok(($group->group_id > 0), "Create and save new group");

# Test create non-unique name
eval { Krang::Group->new(name=>$unique_group_name)->save() };
like($@, qr(duplicate group name), "Test create non-unique name");

# Test load new save
my ($load_group) = Krang::Group->find(name=>$unique_group_name);
ok(ref($load_group), "Can load new group");

# Test delete
eval { $load_group->delete(); };
ok(not($@), "Delete without die");
die ($@) if ($@);

# Try to load deleted group
($load_group) = Krang::Group->find(name=>$unique_group_name);
ok(not(ref($load_group)), "Can't find deleted object");


# Test saving category & desk permissions
my @all_cats = Krang::Category->find(ids_only=>1);
my $test_cat_1 = $all_cats[-1];
my $test_cat_2 = $root_cats[0];
my $test_desk_1 = $all_desks[-1];
my $test_desk_2 = $all_desks[0];

$group = Krang::Group->new(
                           name       => $unique_group_name, 
                           desks      => { $test_desk_1 => "hide", $test_desk_2 => "read-only" }, 
                           categories => { $test_cat_1 => "hide", $test_cat_2 => "read-only" },
                          );
$group->save();
($load_group) = Krang::Group->find(name=>$unique_group_name);
is($load_group->categories($test_cat_1), "hide", "Category permissions saved correctly");
is($load_group->categories($test_cat_2), "read-only", "Category permissions default override");
is($load_group->desks($test_desk_1), "hide", "Desk permissions saved correctly");
is($load_group->desks($test_desk_2), "read-only", "Desk permissions default override");


# Test invalid security levels
$load_group->desks("666"=>"no_such_permission");
eval { $load_group->save() };
like($@, qr(Invalid security level 'no_such_permission' for desk_id '666'), "Die on invalid desk security level");
$load_group->desks_delete("666");

$load_group->categories("777"=>"no_such_permission");
eval { $load_group->save() };
like($@, qr(Invalid security level 'no_such_permission' for category_id '777'), "Die on invalid category security level");
$load_group->categories_delete("777");



##  TO-DO
#
# 1. Test invalid category permissions
# 2. Test invalid desk permissions
# 3. Fix tests to create categories for testing
# 4. Test cache table by selecting directly on data if necessary
#




# Test x_delete MethodMaker hash method
eval { $load_group->save() };
ok(not($@), "desks_delete() and categories_delete()");
die ($@) if ($@);




# Remove test group -- we're done.
$load_group->delete();



##  Debugging output
use Data::Dumper;
print Dumper($group);
