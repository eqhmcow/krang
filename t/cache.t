use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Test::More qw(no_plan);

use_ok('Krang::Cache') or exit;

Krang::Cache::start();
ok(Krang::Cache::active());
Krang::Cache::stop();
ok(not Krang::Cache::active());

Krang::Cache::start();
Krang::Cache::size(5);
is(Krang::Cache::size(), 5);

my @objs = ('a', 'b', 'c', 'd', 'e');
for my $x (0 .. $#objs) {
    Krang::Cache::set('Foo' => $x => $objs[$x]);
}
for my $x (0 .. $#objs) {
    is(Krang::Cache::get('Foo' => $x), $objs[$x]);
}

Krang::Cache::stop();
Krang::Cache::start();

@objs = ('a', 'b', 'c', 'd', 'e', 'f'); 
for my $x (0 .. $#objs) {
    Krang::Cache::set('Foo' => $x => $objs[$x]);
}
ok(not defined Krang::Cache::get('Foo' => 0));
for my $x (1 .. $#objs) {
    is(Krang::Cache::get('Foo' => $x), $objs[$x]);
}

Krang::Cache::stop();
Krang::Cache::start();

@objs = ('a', 'b', 'c', 'd', 'e'); 
for my $x (0 .. $#objs) {
    Krang::Cache::set('Foo' => $x => $objs[$x]);
}
is(Krang::Cache::get('Foo' => 1), 'b');
Krang::Cache::set('Foo' => 5 => 'f');
Krang::Cache::set('Foo' => 6 => 'g');
is(Krang::Cache::get('Foo' => 1), 'b');
ok(not defined Krang::Cache::get('Foo' => 0));
ok(not defined Krang::Cache::get('Foo' => 2));

Krang::Cache::set('Foo' => 10 => 'z');
Krang::Cache::set('Foo' => 11 => 'zz');
Krang::Cache::set('Foo' => 12 => 'zzz');
Krang::Cache::set('Foo' => 13 => 'zzzz');
Krang::Cache::set('Foo' => 14 => 'zzzzz');
ok(not defined Krang::Cache::get('Foo' => $_)) for (0 .. 6);

my ($hits, $loads, $fill) = Krang::Cache::stats();
is ($fill, 5);

