use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::Script;
use Krang::ListGroup;
use Krang::List;
use Krang::ListItem;

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

my $li_1 = Krang::ListItem->new(    list => $list,
                                    data => 'Test top data' );

isa_ok($li_1, 'Krang::ListItem');

$li_1->save();
END { $li_1->delete }; 

my $li_2 = Krang::ListItem->new(  list => $list2,
                                  parent_list_item => $li_1,
                                  data => '2nd level data here' );
$li_2->save();
END { $li_2->delete };

my $li_3 = Krang::ListItem->new(  list => $list2,
                                  parent_list_item => $li_1,
                                  data => 'another 2nd level data here' );
$li_3->save();
END { $li_3->delete };

is($li_2->order, 1, 'first list item in list is order 1');
is($li_3->order, 2, 'second list item in list is order 2');

$li_3->order( 1 );
$li_3->save();

is($li_3->order, 1, 'second list item added to list is now order 1');

# reload $li_2;
$li_2 = (Krang::ListItem->find( list_item_id => $li_2->list_item_id ))[0];
is($li_2->order, 2, 'first list item added to list is now order 2');

