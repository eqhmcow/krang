use strict;
use warnings;

use Krang;
use Test::More 'no_plan';

# make sure it loads
eval {require Krang::Log};
is($@ eq '', 1, 'require successful.');

# Import the module and all the functions
use Krang::Log qw/affirm ASSERT assert should shouldnt debug info critical/;

# set timestamp flag
Krang::Log->timestamp(1);
is(Krang::Log->timestamp(), 1, 'timestamp()');

# set timestamp_format
Krang::Log->timestamp_format("%m-%d %H:%M:%S");
is(Krang::Log->timestamp_format(), "%m-%d %H:%M:%S", 'timestamp_format()');

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


#check all the convenice methods
{
    #turn off timestamps for the test
    Krang::Log->timestamp(0);
    is(Krang::Log->timestamp(), 0, 'timestamp() 2');

    # set log_level to 3, highest logging level so all functions can be tested
    Krang::Log->log_level(3);

    no strict;
    for (qw/debug info critical/) {
        is(&{$_}("$_\n"), "[" . lc($_) . "] $_\n", "$_()");
    }
}
