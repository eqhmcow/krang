use strict;
use warnings;
use Krang::Script;
use Test::More qw(no_plan);

BEGIN { use_ok('Krang::Desk'); }

my $copy_desk = Krang::Desk->new( name => 'copy_test' );
END { $copy_desk->delete(); }

# test simple fields
is($copy_desk->name, 'copy_test');
my $copy_desk_order = $copy_desk->order;
my $copy_desk_id = $copy_desk->desk_id;

my @desks = Krang::Desk->find( desk_id => $copy_desk_id );

# field checks
is($desks[0]->name, $copy_desk->name);
is($desks[0]->order, $copy_desk->order);

my $publish_desk = Krang::Desk->new( name => 'publish_test', order => $copy_desk->order);

END { $publish_desk->delete; }

# make sure orders are correct now
@desks = Krang::Desk->find( desk_id => $copy_desk_id );
is($desks[0]->order, ($copy_desk_order + 1));
is($publish_desk->order, $copy_desk_order);

Krang::Desk->reorder( $copy_desk_id => $publish_desk->order, $publish_desk->desk_id => $desks[0]->order );

# check to see order has reversed
@desks = Krang::Desk->find( desk_id => $copy_desk_id );
is($desks[0]->order, $copy_desk_order);

@desks = Krang::Desk->find( desk_id => $publish_desk->desk_id );
is($desks[0]->order, ($copy_desk_order + 1));

