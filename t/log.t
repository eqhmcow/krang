use Test::More tests => 7;
use strict;
use warnings;

use Krang;

# make sure it loads
BEGIN { use_ok('Krang::Log'); }

# Import the module and all the functions
use Krang::Log qw/debug info critical/;

# set timestamp flag
Krang::Log->timestamp(1);
is(Krang::Log->timestamp(), 1);

# set timestamp_format
Krang::Log->timestamp_format("%m-%d %H:%M:%S");
is(Krang::Log->timestamp_format(), "%m-%d %H:%M:%S");

#check all the convenice methods
{
    #turn off timestamps for the test
    Krang::Log->timestamp(0);
    is(Krang::Log->timestamp(), 0);

    # set log_level to 3, highest logging level so all functions can be tested
    Krang::Log->log_level(3);

    no strict;
    for (qw/debug info critical/) {
        is(&{$_}("$_\n"), "[" . lc($_) . "] $_\n");
    }
}
