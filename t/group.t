## Test script for Krang::Group

use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;
use Krang::Site;
use Krang::Category;
use Krang::Desk;
use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);
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
                    may_checkin_all     => 1,
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
                        may_checkin_all
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


# Test x_delete MethodMaker hash method
eval { $load_group->save() };
ok(not($@), "desks_delete() and categories_delete()");
die ($@) if ($@);


# * Test root category creation (new site) and deletion
my $new_site_uniqueness = "Test". time();
my $new_site = Krang::Site->new( preview_url  => $new_site_uniqueness. 'preview.com',
                                 preview_path => $new_site_uniqueness. 'preview/path/',
                                 publish_path => $new_site_uniqueness. 'publish/path/',
                                 url          => $new_site_uniqueness. 'site.com' );
$new_site->save();
my ($new_cat_id) = Krang::Category->find( site_id=>$new_site->site_id, parent_id=>undef, ids_only=>1 );
($load_group) = Krang::Group->find(name=>$unique_group_name);
my %categories = $load_group->categories();
is($categories{$new_cat_id}, "edit", "New root categories create new category permissions");

# Test permissions cache -- count(*) of category_group_permission_cache for $new_cat_id should == count(groups)
my $group_count = Krang::Group->find(count=>1);
my $dbh = dbh();
my ($perm_cache_count) = $dbh->selectrow_array( qq/ select count(*) from
                                                category_group_permission_cache
                                                where category_id=? /,
                                                {RaiseError=>1}, $new_cat_id );
is($perm_cache_count, $group_count, "Permissions cache created for new category for $group_count groups");

# Delete new site
$new_site->delete();
($load_group) = Krang::Group->find(name=>$unique_group_name);
%categories = $load_group->categories();
is($categories{$new_cat_id}, undef, "Delete root categories delete category permissions");

# Was permissions cache deleted?
($perm_cache_count) = $dbh->selectrow_array( qq/ select count(*) from
                                                category_group_permission_cache
                                                where category_id=? /,
                                                {RaiseError=>1}, $new_cat_id );
is($perm_cache_count, 0, "Permissions cache deleted");


# * Test desk creation and deletion
my $new_desk_uniqueness = "Test". time();
my $new_desk = Krang::Desk->new( name => $new_desk_uniqueness );
my $new_desk_id = $new_desk->desk_id();

($load_group) = Krang::Group->find(name=>$unique_group_name);
my %desks = $load_group->desks();
is($desks{$new_desk_id}, "edit", "New desks create new desk permissions");

# Delete new desk
$new_desk->delete();
($load_group) = Krang::Group->find(name=>$unique_group_name);
%desks = $load_group->desks();
is($desks{$new_desk_id}, undef, "Delete desks deletes new desk permissions");


# Remove test group -- we're done.
$load_group->delete();

