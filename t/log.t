use strict;
use warnings;

use Krang::Script;
use Test::More 'no_plan';

# make sure it loads
eval {require Krang::Log};
is($@ eq '', 1, 'require successful.');

# Import the module and all the functions
use Krang::Log qw/affirm ASSERT assert should shouldnt debug info critical/;

# test assertions if they're on
if (ASSERT) {
    eval {assert(1 == 2) if ASSERT};
    is($@ =~ /assert/, 1, 'assert() works :)');

    eval {
        affirm {
            1 == 1;
            2 == 2;
            0 == 5;
        };
    };
    is($@ =~ /affirm/, 1, 'affirm() works');
    
    eval{should(1, 2) if ASSERT};
    is($@ =~ /should/, 1, 'should() worked');
    
} else {
    # make sure assertions are really off
    eval {assert(1 == 2) if ASSERT};
    is($@ eq '', 1, 'Carp::Assert off');
}
