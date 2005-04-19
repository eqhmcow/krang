use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Test::More qw(no_plan);

BEGIN { use_ok(pkg('Desk')); }

my $copy_desk = pkg('Desk')->new( name => 'copy_test' );
END { $copy_desk->delete(); }

# test simple fields
is($copy_desk->name, 'copy_test');
my $copy_desk_order = $copy_desk->order;
my $copy_desk_id = $copy_desk->desk_id;

my @desks = pkg('Desk')->find( desk_id => $copy_desk_id );

# field checks
is($desks[0]->name, $copy_desk->name);
is($desks[0]->order, $copy_desk->order);

my $publish_desk = pkg('Desk')->new( name => 'publish_test', order => $copy_desk->order);

END { pkg('Desk')->delete($publish_desk->desk_id) }

# make sure orders are correct now
@desks = pkg('Desk')->find( desk_id => $copy_desk_id );
is($desks[0]->order, ($copy_desk_order + 1));
is($publish_desk->order, $copy_desk_order);

pkg('Desk')->reorder( $copy_desk_id => $publish_desk->order, $publish_desk->desk_id => $desks[0]->order );

# check to see order has reversed
@desks = pkg('Desk')->find( desk_id => $copy_desk_id );
is($desks[0]->order, $copy_desk_order);

@desks = pkg('Desk')->find( desk_id => $publish_desk->desk_id );
is($desks[0]->order, ($copy_desk_order + 1));

