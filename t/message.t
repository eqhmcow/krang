use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Test::More qw(no_plan);
use Krang::ClassLoader 'Script';
BEGIN {use_ok(pkg('Message'));}

use Krang::ClassLoader Message => qw(add_message get_messages clear_messages);

add_message("test1");
is(get_messages(), 1);
is((get_messages())[0], "This is a test.");

add_message("test1");
is(get_messages(), 1);
is(get_messages(dups => 1), 2);
is(get_messages(keys => 1), 4);

clear_messages();
is(get_messages(), 0);

add_message("test2", test => 'foo');
is(get_messages(), 1);
is(get_messages(dups => 1), 1);
is((get_messages())[0], "This is a foo.");

add_message("test2", test => 'bar');
is(get_messages(), 2);
is(get_messages(dups => 1), 2);
is((get_messages())[1], "This is a bar.");

add_message("test3", test => 'foo', foo => 'bar');
is(get_messages(), 3);
is((get_messages())[2], "This is a foo foo foo bar.");

package Test::Module1;
use Krang::ClassLoader Message => qw(add_message get_messages clear_messages);
add_message("test1");
add_message("test2", test => 'zumthing');
Test::More::is(get_messages(), 5);
Test::More::is((get_messages())[3], "Now for something completely different.");
Test::More::is((get_messages())[4], "Now for zumthing completely different.");

package Test::Module2;
use Krang::ClassLoader Message => qw(add_message get_messages clear_messages);
add_message("test1");
add_message("test1", from_module => 'Test::Module1');
Test::More::is(get_messages(dups => 1), 7);
Test::More::is((get_messages(dups => 1))[5], "Another test, oh joy.");
Test::More::is((get_messages(dups => 1))[6], "Now for something completely different.");
