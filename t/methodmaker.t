use Krang::ClassFactory qw(pkg);
use Test::More tests => 11;
use strict;
use warnings;

BEGIN { use_ok(pkg('MethodMaker')) }

package Foo;
use Krang::ClassLoader MethodMaker => new => 'new',
  get                              => 'id',
  get_set                          => [qw(bar baz)];

package main;

my $foo = Foo->new();
isa_ok($foo, 'Foo');
is($foo->bar,        undef);
is($foo->bar('bar'), 'bar');
is($foo->bar,        'bar');
is($foo->bar(undef), undef);
is($foo->bar(),      undef);
ok(!$foo->can('foo_clear'));
is($foo->id(), undef);
$foo->{id} = 10;
is($foo->id(), 10);
eval { $foo->id(10) };
like($@, qr/illegal attempt to set readonly attribute/);

