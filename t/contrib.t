use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;

BEGIN { use_ok('Krang::Contrib') }

# create new contributor object
my $contrib = Krang::Contrib->new(prefix => 'Mr', first => 'Matthew', middle => 'Charles', last => 'Vella', email => 'mvella@thepirtgroup.com');
isa_ok($contrib, 'Krang::Contrib');

$contrib->contrib_type_ids(1,3);
$contrib->selected_contrib_type(1);

my @contrib_type_ids = $contrib->contrib_type_ids();
is("@contrib_type_ids", "1 3");
is($contrib->selected_contrib_type, 1);

eval { $contrib->selected_contrib_type(2) };
like($@, qr/bad/);

$contrib->save();

my $contrib_id = $contrib->contrib_id();

my @contrib_object = Krang::Contrib->find( contrib_id => $contrib_id );

my $contrib2 = $contrib_object[0];

is($contrib2->first, 'Matthew');
is($contrib2->contrib_type_ids()->[0], 1);
is($contrib2->contrib_type_ids()->[1], 3);

$contrib2->contrib_type_ids(2,4);

$contrib2->save();

my @contrib_object2 = Krang::Contrib->find( full_name => 'matt vella' );

my $contrib3 = $contrib_object2[0];

is($contrib3->contrib_id, $contrib_id);

# test count
my $count = Krang::Contrib->find( full_name => 'matt vella',
                                  count     => 1 );
is($count, 1);


# Test ability to make a change to an existing record and save()
$contrib2->first('George');
$contrib2->save();

# Has contrib2 been updated in database?
my ($contrib2loaded) = Krang::Contrib->find( contrib_id => $contrib2->contrib_id() );
is($contrib2loaded->first(), 'George');


# Clean up added contrib
$contrib2->delete();

