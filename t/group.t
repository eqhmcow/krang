## Test script for Krang::Group

use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;

BEGIN { use_ok('Krang::Group') }

# Variable for our work
my $group = 0;

# Create a new group object w/o params
eval { $group = Krang::Group->new() };
ok(not ($@), 'Create a new group object w/o params');
die ($@) if ($@);
ok(ref($group), 'Create a new group object w/o params');
isa_ok($group, "Krang::Group");


# Create a new group object with params
my %test_params = ( name => 'Car Editors',
                    categories    => { 1 => 'read-only', 
                                       2 => 'edit', 
                                       23 => 'hide' },
                    desks         => { },
                    assets  => { },
                    may_publish         => 1,
                    admin_users         => 1,
                    admin_users_limited => 1,
                    admin_groups        => 1,
                    admin_contribs      => 1,
                    admin_sites         => 1,
                    admin_categories    => 1,
                    admin_jobs          => 1,
                    admin_desks         => 1,
                    admin_prefs         => 1 );

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
                        admin_prefs );

for (@scalar_params) {
    my $val = "Test $_";
    ok($group->$_($val), "Set $_");
    is($group->$_(), $val, "Get $_");
}

# Test hash methods
my @hash_params = qw( categories
                      desks
                      assets );

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



##  Debugging output
use Data::Dumper;
print Dumper($group);
