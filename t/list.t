use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::Script;
use Krang::ListGroup;
use Krang::List;

# create a site and some categories to put stories in
my $lg = Krang::ListGroup->new( name  => 'test_abc_123'.time,
                                description => 'blah blah',
                                );
isa_ok($lg, 'Krang::ListGroup');
$lg->save();
END { $lg->delete() };

my $list = Krang::List->new(    list_group_id => $lg->list_group_id,
                                name => 'test_list_1',
                            );

isa_ok($list, 'Krang::List');
$list->save;
END { $list->delete() };

my $list2 = Krang::List->new(   list_group_id => $lg->list_group_id,
                                name => 'test_list_2',
                                parent_list_id => $list->list_id
                            );

$list2->save;
END { $list2->delete() };

my @found = Krang::List->find( parent_list_id => $list->list_id );

is( $found[0]->name, $list2->name, "list found by parent_list_id" );

@found = Krang::List->find( list_group_id => $lg->list_group_id );

is( @found, 2, '2 Krang::Lists found in Krang::ListGroup');
