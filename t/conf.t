use Test::More tests => 14;
use strict;
use warnings;

use File::Temp qw(tempfile);

# setup a test conf file
my ($fh, $filename) = tempfile();
print $fh <<CONF;
<Instance instance_one>
  ElementSet Flex
  DBName test
  DBUser test
  DBPass test
</Instance>

<Instance instance_two>
  ElementSet LA
  DBName test2
  DBUser test2
  DBPass test2
</Instance>
CONF
close($fh);

# use this file as krang.conf
$ENV{KRANG_CONF} = $filename;
ok(-e $filename);

eval "use_ok('Krang::Conf')";
die $@ if $@;

# get the globals, all ways
ok(Krang::Conf->get("KrangRoot"));
ok(Krang::Conf->KrangRoot);

Krang::Conf->import(qw(KrangRoot DBName));
ok(KrangRoot());
ok(not defined DBName());

Krang::Conf->instance("instance_one");
is(Krang::Conf->instance, "instance_one");
ok(KrangRoot());
is(Krang::Conf->get("DBName"), "test");
is(DBName(), "test");

Krang::Conf->instance("instance_two");
is(Krang::Conf->instance, "instance_two");
ok(KrangRoot());
is(Krang::Conf->get("DBName"), "test2");
is(DBName(), "test2");
