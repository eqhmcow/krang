use strict;
use warnings;
use Krang::Script;
use Test::More qw(no_plan);

BEGIN { use_ok('Krang::Desk'); }

my $copy_desk = Krang::Desk->new( name => 'qop', order => 4 );

$copy_desk->delete();
