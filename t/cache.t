use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::Script;
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);
BEGIN { use_ok('Krang::Cache') }

# can create a new cache?
my $cache = Krang::Cache->new(name => 'test');
isa_ok($cache, 'Krang::Cache');

# does the cache file exist
my $file = 
  catfile(KrangRoot, 'data', 'cache', Krang::Conf->instance, 'test');
ok(-f $file);

# try to read a non-existent entry
is($cache->read('foo'), undef);

# write an entry and try to read it back
$cache->write(100 => ['bing', 'bong']);
ok($cache->read(100));
isa_ok($cache->read(100), 'ARRAY');
is($cache->read(100)->[0], 'bing');
is($cache->read(100)->[1], 'bong');

# replace it
$cache->write(100 => {biff => 'bap'});
ok($cache->read(100));
isa_ok($cache->read(100), 'HASH');
is($cache->read(100)->{biff}, 'bap');

# delete it
$cache->delete(100);
is($cache->read(100), undef);

# add a few
$cache->write(1 => \2);
is(${$cache->read(1)}, 2);
$cache->write(3 => \4);
is(${$cache->read(3)}, 4);
$cache->write(5 => \6);
is(${$cache->read(5)}, 6);

# clear them all
$cache->clear;
is($cache->read(1), undef);
is($cache->read(3), undef);
is($cache->read(5), undef);

# clean up
undef $cache;
unlink $file;
