use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::Script;
use Krang::ListGroup;

# create a site and some categories to put stories in
my $lg = Krang::ListGroup->new( name  => 'test_abc_123'.time,
                                description => 'blah blah',
                                );
isa_ok($lg, 'Krang::ListGroup');
$lg->save();

my ($lg_f) = Krang::ListGroup->find ( list_group_id => $lg->list_group_id );

isa_ok($lg_f, 'Krang::ListGroup');

is( $lg_f->description, $lg->description, "description was saved and retrieved" );

END { $lg->delete() }
