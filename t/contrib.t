use Test::More qw(no_plan);
use strict;
use warnings;
use Krang;

BEGIN { use_ok('Krang::Contrib') }

# create new contributor object
my $contrib = Krang::Contrib->new(prefix => 'Mr', first => 'Matthew', middle => 'Charles', last => 'Vella', email => 'mvella@thepirtgroup.com');
isa_ok($contrib, 'Krang::Contrib');

$contrib->contrib_type_ids(1,3);

my @contrib_type_ids = $contrib->contrib_type_ids();
is("@contrib_type_ids", "1 3");

$contrib->save();

my $contrib_id = $contrib->contrib_id();

my @contrib_object = Krang::Contrib->find( contrib_id => $contrib_id );

my $contrib2 = $contrib_object[0];

is($contrib2->first, 'Matthew');

$contrib2->contrib_type_ids(2,4);

$contrib2->save();

my @contrib_object2 = Krang::Contrib->find( full_name => 'matt vella' );

my $contrib3 = $contrib_object2[0];

is($contrib3->contrib_id, $contrib_id);

$contrib2->delete();
