use strict;
use warnings;

use Krang::Script;
use Test::More qw(no_plan);

use_ok('Krang::AddOn') or exit;

# make sure requirements are enforced
eval { my $bad =  Krang::AddOn->new() };
like($@, qr/missing required/i);
eval { my $bad =  Krang::AddOn->new(name => 'bad') };
like($@, qr/missing required/i);
eval { my $bad =  Krang::AddOn->new(version => 10) };
like($@, qr/missing required/i);

# create a good one
my $addon = Krang::AddOn->new(name => 'Foo', version => 3);
isa_ok($addon, 'Krang::AddOn');

# save it
$addon->save();

# should be in the list
my @addons = Krang::AddOn->find();
ok(grep { $_->name eq $addon->name } @addons);

# add another
my $addon2 = Krang::AddOn->new(name => 'Bar', version => 4);
isa_ok($addon2, 'Krang::AddOn');
$addon2->save();

# both there?
@addons = Krang::AddOn->find();
ok(grep { $_->name eq $addon->name } @addons);
ok(grep { $_->name eq $addon2->name } @addons);

# find by name
my ($one) = Krang::AddOn->find(name => 'Foo');
is($one->name, $addon->name);
is($one->version, $addon->version);

my ($two) = Krang::AddOn->find(name => 'Bar');
is($two->name, $addon2->name);
is($two->version, $addon2->version);

# delete the first
$addon->delete();
@addons = Krang::AddOn->find();
ok(not grep { $_->name eq $addon->name } @addons);
ok(grep { $_->name eq $addon2->name } @addons);

# make a change and save
is($addon2->version, 4);
$addon2->version(10);
is($addon2->version, 10);
$addon2->save();
my ($loaded) = Krang::AddOn->find(name => 'Bar');
is($loaded->version, 10);

# cleanup
$loaded->delete();
