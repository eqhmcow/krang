use Test::More tests => 17;
use strict;
use warnings;

use File::Temp qw(tempfile);

# setup a test conf file
my ($fh, $filename) = tempfile();
print $fh <<CONF;
ElementLibrary /usr/local/krang_elements

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
is(Krang::Conf->get("ElementLibrary"), "/usr/local/krang_elements");
ok(Krang::Conf->KrangRoot);
is(Krang::Conf->ElementLibrary, "/usr/local/krang_elements");

Krang::Conf->import(qw(KrangRoot ElementLibrary DBName));
ok(KrangRoot());
is(ElementLibrary(), "/usr/local/krang_elements");
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
