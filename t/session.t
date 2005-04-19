use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
BEGIN { ok(1) }
use Krang::ClassLoader Session => qw(%session);
BEGIN { pkg('Session')->create(); }

# loading Krang should provide a session
my $id = $session{_session_id};
ok($id);
is(length($id), 32);

# set some keys
$session{foo} = 'bar';
$session{bar} = [ qw(bing bang boom) ];

# did that work?
is($session{foo}, 'bar');
isa_ok($session{bar}, 'ARRAY');
is($session{bar}[0], 'bing');
is($session{bar}[2], 'boom');

# unload it
pkg('Session')->unload();

# really gone?
my @keys = keys(%session);
is(@keys, 0);

# load up
ok(pkg('Session')->validate($id));
pkg('Session')->load($id);

# did that work?
is($session{foo}, 'bar');
isa_ok($session{bar}, 'ARRAY');
is($session{bar}[0], 'bing');
is($session{bar}[2], 'boom');

# vanish, I say!
pkg('Session')->delete();
ok(not pkg('Session')->validate($id));

# really gone?
@keys = keys(%session);
is(@keys, 0);

# really, really gone?
eval { pkg('Session')->load($id) };
like($@, qr/does not exist/);
