## Test script for Krang::Group

use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;


BEGIN { use_ok('Krang::Group') }

# Create a new group object w/o params
my $group;
eval { $group = Krang::Group->new() };
ok(not ($@), 'new() not die');
ok(ref($group), 'Create a new group object w/o params');
isa_ok($group, "Krang::Group");

my %test_params = ();
