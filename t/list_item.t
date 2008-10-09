use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'ListGroup';
use Krang::ClassLoader 'List';
use Krang::ClassLoader 'ListItem';

# create a site and some categories to put stories in
my $lg = pkg('ListGroup')->new(
    name        => 'test_abc_123' . time,
    description => 'blah blah',
);
isa_ok($lg, 'Krang::ListGroup');
$lg->save();
END { $lg->delete() }

my $list = pkg('List')->new(
    list_group_id => $lg->list_group_id,
    name          => 'test_list_1',
);

isa_ok($list, 'Krang::List');
$list->save;
END { $list->delete() }

my $list2 = pkg('List')->new(
    list_group_id  => $lg->list_group_id,
    name           => 'test_list_2',
    parent_list_id => $list->list_id
);

$list2->save;
END { $list2->delete() }

my $li_1 = pkg('ListItem')->new(
    list => $list,
    data => 'Test top data'
);

isa_ok($li_1, 'Krang::ListItem');

$li_1->save();
END { $li_1->delete }

my $li_2 = pkg('ListItem')->new(
    list             => $list2,
    parent_list_item => $li_1,
    data             => '2nd level data here'
);
$li_2->save();
END { $li_2->delete }

my $li_3 = pkg('ListItem')->new(
    list             => $list2,
    parent_list_item => $li_1,
    data             => 'another 2nd level data here'
);
$li_3->save();
END { $li_3->delete }

is($li_2->order, 1, 'first list item in list is order 1');
is($li_3->order, 2, 'second list item in list is order 2');

$li_3->order(1);
$li_3->save();

is($li_3->order, 1, 'second list item added to list is now swapped to order 1');

# reload $li_2;
$li_2 = (pkg('ListItem')->find(list_item_id => $li_2->list_item_id))[0];
is($li_2->order, 2, 'first list item added to list is now swapped to order 2');

my $li_4 = pkg('ListItem')->new(
    list             => $list2,
    parent_list_item => $li_1,
    data             => '3rd 2nd level data here',
    order            => 1
);

$li_4->save();
END { $li_4->delete }

is($li_4->order, 1, 'third list item added to list is placed at order 1');

# reload $li_2;
$li_3 = (pkg('ListItem')->find(list_item_id => $li_3->list_item_id))[0];
is($li_3->order, 2, 'second list item added to list is now shifted to order 2');

# reload $li_2;
$li_2 = (pkg('ListItem')->find(list_item_id => $li_2->list_item_id))[0];
is($li_2->order, 3, 'first list item added to list is now shifted to order 3');

