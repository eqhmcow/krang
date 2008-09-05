## Test script for Krang::Group

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Desk';
use Krang::ClassLoader 'User';
use Krang::ClassLoader Conf => qw(KrangRoot InstanceElementSet);
use Krang::ClassLoader DB => qw(dbh);

use Krang::ClassLoader 'Test::Content';


use File::Spec::Functions qw(catfile);

BEGIN {
        my $found;
    foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        if (InstanceElementSet eq 'TestSet1' || InstanceElementSet eq 'Default') {
            $found = 1;
            last;
        }
    }

    unless ($found) {
        eval "use Test::More skip_all => 'test requires an instance using TestSet1 or Default';";
    } else {
        eval "use Test::More qw(no_plan);";
    }
    die $@ if $@;
}


use_ok(pkg('Group'));

# create some categories and clean them up when finished
# Site params
my $preview_url = 'grouptest.preview.com';
my $publish_url = 'grouptest.com';
my $preview_path = KrangRoot . '/tmp/kranggrouptest_preview';
my $publish_path = KrangRoot . '/tmp/kranggrouptest_publish';


my $creator = pkg('Test::Content')->new;

my $site = $creator->create_site(preview_url  => $preview_url,
                                 publish_url  => $publish_url,
                                 preview_path => $preview_path,
                                 publish_path => $publish_path
                                );

my ($root_cat) = pkg('Category')->find(site_id => $site->site_id());

my @cats;
for (1..3) {
    push @cats, $creator->create_category(
                                          dir     => 'grouptest_' . $_,
                                          parent  => $root_cat->category_id
                                         );
}

END {
    $creator->cleanup();
}


# Variable for our work
my $group = 0;

# Create a new group object w/o params
eval { $group = pkg('Group')->new() };
ok(not ($@), 'Create a new group object w/o params');
die ($@) if ($@);
ok(ref($group), 'Create a new group object w/o params');
isa_ok($group, "Krang::Group");


# Verify that new group has inherited existing root categories and set them to "edit" by default
my @root_cats = pkg('Category')->find(ids_only=>1, parent_id=>undef);
my $group_categories = $group->categories();
foreach my $cat (@root_cats) {
    is($group_categories->{$cat}, "edit", "Root category '$cat' defaults to 'edit'");
}


# Verify that new group has inherited existing desks and set them to "edit" by default
my @all_desks = pkg('Desk')->find(ids_only=>1);
my $group_desks = $group->desks();
foreach my $desk (@all_desks) {
    is($group_desks->{$desk}, "edit", "Desk '$desk' defaults to 'edit'");
}


# Create a new group object with params
my %test_params = ( name => 'Car Editors',
                    categories           => { 1 => 'read-only', 
					      2 => 'edit', 
					      23 => 'hide' },
                    desks                => { },
                    may_publish          => 1,
                    may_checkin_all      => 1,
                    admin_users          => 1,
                    admin_users_limited  => 1,
                    admin_groups         => 1,
                    admin_contribs       => 1,
                    admin_sites          => 1,
                    admin_categories     => 1,
                    admin_categories_ftp => 1,
                    admin_jobs           => 1,
                    admin_scheduler      => 1,
                    admin_desks          => 1,
                    admin_lists          => 1,
                    admin_delete         => 1,
                    asset_story          => 'edit',
                    asset_media          => 'read-only',
                    asset_template       => 'hide' );

$group = 0;
eval { $group = pkg('Group')->new(%test_params) };
ok(not ($@), 'Create a new group object with params');
die ($@) if ($@);
ok(ref($group), 'Create a new group object with params');
isa_ok($group, "Krang::Group");


# Test invalid create param
eval { pkg('Group')->new(%test_params, no_such_param => 1) };
like($@, qr(Can't locate object method "no_such_param" via package .*::Group), 'Test invalid create param');


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
                        admin_categories_ftp
                        admin_jobs
                        admin_scheduler
                        admin_desks
                        admin_lists
                        admin_delete
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

# make sure our id_meth and uuid_meth are correct
my $method = $group->id_meth;
is($group->$method, $group->group_id, 'id_meth() is correct');
$method = $group->uuid_meth;
is($group->$method, $group->group_uuid, 'uuid_meth() is correct');


# Test find() for invalid arg handling
eval { pkg('Group')->find( no_such_find_arg => 1) };
like($@, qr(Invalid find arg), 'Test invalid find arg');


# Test find(count=>1)
my $count = pkg('Group')->find(count=>1);
ok(($count =~ /^\d+$/), "Test find(count=>1)");


# Test find(ids_only=>1)
my @group_ids = ( pkg('Group')->find(ids_only=>1) );
is(scalar(@group_ids), $count, "find(ids_only=>1)");
like($group_ids[0], qr(^\d+$), "ids_only really returns IDs");


# Test find(group_ids=>[])
eval { pkg('Group')->find(group_ids=>'bad input') };
like($@, qr(group_ids must be an array ref), 'Test bad scalar input to group_ids');

eval { pkg('Group')->find(group_ids=>[1, 2, 3, '4bad input']) };
like($@, qr(group_ids array ref may only contain numeric IDs), 'Test bad array ref input to group_ids');

my $count_group_ids = pkg('Group')->find(count=>1, group_ids=>[1, 2, 505]);
is($count_group_ids, 2, "Test find(group_ids=>[])");


# Test find(group_id=>1)
eval { ($group) = pkg('Group')->find(group_id=>1) };
is($group->group_id, "1", "Test find(group_id=>1)");


# Test save
my $unique_group_name = "Test ". time();
$group = pkg('Group')->new();
$group->name($unique_group_name);
eval { $group->save(); };
ok(not($@), "Save without die");
die ($@) if ($@);
ok(($group->group_id > 0), "Create and save new group");
ok($group->group_uuid);

# Test create non-unique name
eval { pkg('Group')->new(name=>$unique_group_name)->save() };
like($@, qr(duplicate group name), "Test create non-unique name");

# Test load new save
my ($load_group) = pkg('Group')->find(name=>$unique_group_name);
ok(ref($load_group), "Can load new group");

# Test delete
eval { $load_group->delete(); };
ok(not($@), "Delete without die");
die ($@) if ($@);

# Try to load deleted group
($load_group) = pkg('Group')->find(name=>$unique_group_name);
ok(not(ref($load_group)), "Can't find deleted object");


# Test saving category & desk permissions
my @all_cats = pkg('Category')->find(ids_only=>1);
my $test_cat_1 = $all_cats[-1];
my $test_cat_2 = $root_cats[0];
my $test_desk_1 = $all_desks[-1];
my $test_desk_2 = $all_desks[0];

$group = pkg('Group')->new(
                           name       => $unique_group_name, 
                           desks      => { $test_desk_1 => "hide", $test_desk_2 => "read-only" }, 
                           categories => { $test_cat_1 => "hide", $test_cat_2 => "read-only" },
                          );
$group->save();
($load_group) = pkg('Group')->find(name=>$unique_group_name);
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
my $new_site = pkg('Site')->new( preview_url  => $new_site_uniqueness. 'preview.com',
                                 preview_path => $new_site_uniqueness. 'preview/path/',
                                 publish_path => $new_site_uniqueness. 'publish/path/',
                                 url          => $new_site_uniqueness. 'site.com' );
$new_site->save();
my ($new_cat_id) = pkg('Category')->find( site_id=>$new_site->site_id, parent_id=>undef, ids_only=>1 );
($load_group) = pkg('Group')->find(name=>$unique_group_name);
my %categories = $load_group->categories();
is($categories{$new_cat_id}, "edit", "New root categories create new category permissions");

# Test permissions cache -- count(*) of category_group_permission_cache for $new_cat_id should == count(groups)
my $user_count = pkg('User')->find(count=>1);
my $dbh = dbh();
my ($perm_cache_count) = $dbh->selectrow_array( qq/ select count(*) from
                                                user_category_permission_cache
                                                where category_id=? /,
                                                {RaiseError=>1}, $new_cat_id );
is($perm_cache_count, $user_count, "Permissions cache created for new category for $user_count users");

# Delete new site
$new_site->delete();
($load_group) = pkg('Group')->find(name=>$unique_group_name);
%categories = $load_group->categories();
is($categories{$new_cat_id}, undef, "Delete root categories delete category permissions");

# Was permissions cache deleted?
($perm_cache_count) = $dbh->selectrow_array( qq/ select count(*) from
                                                user_category_permission_cache
                                                where category_id=? /,
                                                {RaiseError=>1}, $new_cat_id );
is($perm_cache_count, 0, "Permissions cache deleted");


# * Test desk creation and deletion
my $new_desk_uniqueness = "Test". time();
my $new_desk = pkg('Desk')->new( name => $new_desk_uniqueness );
my $new_desk_id = $new_desk->desk_id();

($load_group) = pkg('Group')->find(name=>$unique_group_name);
my %desks = $load_group->desks();
is($desks{$new_desk_id}, "edit", "New desks create new desk permissions");

# Delete new desk
$new_desk->delete();
($load_group) = pkg('Group')->find(name=>$unique_group_name);
%desks = $load_group->desks();
is($desks{$new_desk_id}, undef, "Delete desks deletes new desk permissions");


# Remove test group -- we're done.
$load_group->delete();



### Test user_*_permissions() methods
#

# user_desk_permissions()
my %user_desk_permissions;
eval { %user_desk_permissions = pkg('Group')->user_desk_permissions() };

# Check that we didn't die
ok(not($@), "Krang::Group->user_desk_permissions()");
die ($@) if ($@);

# Check that we can get a hash of all desks
ok(%user_desk_permissions, "Got desk permissions");

# Check that select for individual desk matches hash
is($user_desk_permissions{1}, pkg('Group')->user_desk_permissions(1), "Desk 1 permissions match");


## Check that desk permissions combine correctly
#
my $desk_perm_test_desk = pkg('Desk')->new(name=>"desk_perm_test_desk");
my $desk_perm_test_desk_id = $desk_perm_test_desk->desk_id;

# Change admin group to have "hide" access to new desk
my ($admin_group) = pkg('Group')->find(group_id=>1);
$admin_group->desks($desk_perm_test_desk_id=>"hide");
$admin_group->save();

# Set up new group with "read-only" access to new desk.
my $desk_perm_test_group = pkg('Group')->new();
$desk_perm_test_group->desks($desk_perm_test_desk_id=>"read-only");
$desk_perm_test_group->save();

# Admin should only have "hide" access to desk now
is( pkg('Group')->user_desk_permissions($desk_perm_test_desk_id),
    "hide",
    "Admin has 'hide' desk access" );

# Add new group to Admin user and check again.  Access should now be "read-only"
my ($admin_user) = pkg('User')->find(login=>'system', hidden => 1);
$admin_user->group_ids_push( $desk_perm_test_group->group_id );
$admin_user->save();
is( pkg('Group')->user_desk_permissions($desk_perm_test_desk_id),
    "read-only",
    "Admin has 'read-only' desk access" );

# Change permissions for admin group, for this desk, to "edit".  Re-check -- should be "edit" now.
$admin_group->desks($desk_perm_test_desk_id=>"edit");
$admin_group->save();
is( pkg('Group')->user_desk_permissions($desk_perm_test_desk_id),
    "edit",
    "Admin has 'edit' desk access" );

# Clean up
$admin_user->group_ids_pop();
$admin_user->save();
$desk_perm_test_group->delete();
$desk_perm_test_desk->delete();




# user_asset_permissions()
my %user_asset_permissions;
eval { %user_asset_permissions = pkg('Group')->user_asset_permissions() };

# Check that we didn't die
ok(not($@), "Krang::Group->user_asset_permissions()");
die ($@) if ($@);

# Check that we can get a hash of all assets
ok(%user_asset_permissions, "Got asset permissions");

# Check that select for individual asset matches hash
is( $user_asset_permissions{"media"},
    pkg('Group')->user_asset_permissions("media"),
    "Asset 'media' permissions match" );


## Check that asset permissions combine correctly
#

# Change admin group to have "hide" access to media
($admin_group) = pkg('Group')->find(group_id=>$admin_user->group_ids());
$admin_group->asset_media("hide");
$admin_group->save();

# Set up new group with "read-only" access to media.
my $asset_perm_test_group = pkg('Group')->new( name=>"asset_perm_test_group" );
$asset_perm_test_group->asset_media("read-only");
$asset_perm_test_group->save();

# Admin should only have "hide" access to media now
is( pkg('Group')->user_asset_permissions("media"),
    "hide",
    "Admin has 'hide' access to media" );

# Add new group to Admin user and check again.  Access should now be "read-only"
($admin_user) = pkg('User')->find(login => 'system', hidden => 1);
$admin_user->group_ids_push( $asset_perm_test_group->group_id );
$admin_user->save();
is( pkg('Group')->user_asset_permissions("media"),
    "read-only",
    "Admin has 'read-only' access to media" );

# Change permissions for admin group, for media, to "edit".  Re-check -- should be "edit" now.
$admin_group->asset_media("edit");
$admin_group->save();
is( pkg('Group')->user_asset_permissions("media"),
    "edit",
    "Admin has 'edit' access to media" );

# Clean up
$admin_user->group_ids_pop;
$admin_user->save();
$asset_perm_test_group->delete();




# user_admin_permissions()
my %user_admin_permissions;
eval { %user_admin_permissions = pkg('Group')->user_admin_permissions() };

# Check that we didn't die
ok(not($@), "Krang::Group->user_admin_permissions()");
die ($@) if ($@);

# Check that we can get a hash of all admins
ok(%user_admin_permissions, "Got admin permissions");

# Check that select for individual admin matches hash
is( $user_admin_permissions{"admin_delete"},
    pkg('Group')->user_admin_permissions("admin_delete"),
    "Admin permissions 'admin_delete' match");


## Check that admin permissions combine correctly
#

# Change admin group to have may_publish=>0 access
($admin_group) = pkg('Group')->find(group_id=>1);
$admin_group->may_publish(0);
$admin_group->save();

# Set up new group with may_publish=>1 access.
my $admin_perm_test_group = pkg('Group')->new( name=>"admin_perm_test_group" );
$admin_perm_test_group->may_publish(1);
$admin_perm_test_group->save();

# Admin should only may_publish=>0 access
is( pkg('Group')->user_admin_permissions("may_publish"),
    0,
    "Admin has may_publish=>0 access" );

# Add new group to Admin user and check again.  Access should now be "read-only"
($admin_user) = pkg('User')->find(login => 'system', hidden => 1);
$admin_user->group_ids_push( $admin_perm_test_group->group_id );
$admin_user->save();
is( pkg('Group')->user_admin_permissions("may_publish"),
    1,
    "Admin has may_publish=>1 access" );


## Check admin_users_limited
#

# Set test group and admin group to admin_users_limited=>1
$admin_perm_test_group->admin_users_limited(1);
$admin_perm_test_group->save();
$admin_group->admin_users_limited(1);
$admin_group->save();

# Test that admin is admin_users_limited=>1;
is( pkg('Group')->user_admin_permissions("admin_users_limited"),
    1,
    "Admin has admin_users_limited=>1 access" );

# Change admin group to admin_users_limited=>0.  Re-test.
$admin_group->admin_users_limited(0);
$admin_group->save();
is( pkg('Group')->user_admin_permissions("admin_users_limited"),
    0,
    "Admin has admin_users_limited=>0 access" );

# fix may_publish permissions for the admin group
$admin_group->may_publish(1);
$admin_group->save();


# try creating a four level deep category hierarchy, setting the
# second level hidden.  All categories below should be hidden too.
{
    my $site = pkg('Site')->new(preview_url  => 'prev.hubba.com',
                                url          => 'hubba.com',
                                preview_path => '/tmp/hubba.pre',
                                publish_path => '/tmp/hubba',
                               );
    $site->save();
    my ($root) = pkg('Category')->find(site_id => $site->site_id());

    my $one = pkg('Category')->new(dir => 'one',
                                   parent_id => $root->category_id);
    $one->save();
    my $two = pkg('Category')->new(dir => 'two',
                                   parent_id => $one->category_id);
    $two->save();
    my $three = pkg('Category')->new(dir => 'three',
                                     parent_id => $two->category_id);
    $three->save();
    my $four = pkg('Category')->new(dir => 'four',
                                    parent_id => $three->category_id);
    $four->save();
    
    # make sure that worked out
    is($one->url, 'hubba.com/one/');
    is($two->url, 'hubba.com/one/two/');
    is($three->url, 'hubba.com/one/two/three/');
    is($four->url, 'hubba.com/one/two/three/four/');

    # set one to be hidden
    my $group = pkg('Group')->new(name => 'hubba');
    $group->categories($one->category_id => 'hide');
    $group->save();
    $admin_user->group_ids_push( $group->group_id );
    $admin_user->save();

    # now make sure the kids don't come back from find
    my @cats = pkg('Category')->find(may_see => 1);
    ok(grep { $_->category_id == $root->category_id } @cats);
    ok(not(grep { $_->category_id == $one->category_id } @cats),
       '/one should be hidden');
    ok(not(grep { $_->category_id == $two->category_id } @cats),
       '/one/two should be hidden');
    ok(not(grep { $_->category_id == $three->category_id } @cats),
       '/one/two/three should be hidden');
    ok(not(grep { $_->category_id == $four->category_id } @cats),
      '/one/two/three/four should be hidden');

    # try rebuilding
    pkg('Group')->rebuild_category_cache;
    @cats = pkg('Category')->find(may_see => 1);
    ok(grep { $_->category_id == $root->category_id } @cats);
    ok(not(grep { $_->category_id == $one->category_id } @cats),
       '/one should be hidden');
    ok(not(grep { $_->category_id == $two->category_id } @cats),
       '/one/two should be hidden');
    ok(not(grep { $_->category_id == $three->category_id } @cats),
       '/one/two/three should be hidden');
    ok(not(grep { $_->category_id == $four->category_id } @cats),
      '/one/two/three/four should be hidden');


    $admin_user->group_ids_pop();
    $admin_user->save();
    $group->delete();
    $_->delete for ($four, $three, $two, $one, $site);
}



# Clean up
$admin_user->group_ids_pop();
$admin_user->save();
$admin_perm_test_group->delete();


