use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::Script;
use Krang::Alert;

my $alert = Krang::Alert->new();

isa_ok($alert, 'Krang::Alert');
