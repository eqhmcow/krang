use Test::More qw(no_plan);
use strict;
use warnings;
use Krang;

BEGIN { use_ok('Krang::Contrib') }

# create new contributor object
my $contrib = Krang::Contrib->new(prefix => 'Mr', first => 'Matt', middle => 'Charles', last => 'Vella', email => 'mvella@thepirtgroup.com');
isa_ok($contrib, 'Krang::Contrib');

$contrib->contrib_types(1,3);

my @contrib_types = $contrib->contrib_types();
is("@contrib_types", "1 3");

$contrib->save();

$contrib->contrib_types(2,4);

$contrib->save();

$contrib->delete();
