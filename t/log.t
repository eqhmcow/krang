use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Test::More 'no_plan';

# make sure it loads
BEGIN { use_ok(pkg('Log')) }

# Import the module and all the functions
use Krang::ClassLoader Log => qw/affirm ASSERT assert should shouldnt debug info critical/;

# test assertions if they're on
if (ASSERT) {
    eval { assert(1 == 2) if ASSERT };
    is($@ =~ /assert/, 1, 'assert() works :)');

    eval {
        affirm {
            1 == 1;
            2 == 2;
            0 == 5;
        };
    };
    is($@ =~ /affirm/, 1, 'affirm() works');

    eval { should(1, 2) if ASSERT };
    is($@ =~ /should/, 1, 'should() worked');

} else {

    # make sure assertions are really off
    eval { assert(1 == 2) if ASSERT };
    is($@ eq '', 1, 'Carp::Assert off');
}
