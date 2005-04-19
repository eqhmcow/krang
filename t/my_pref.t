use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Test::More qw(no_plan);

BEGIN { use_ok(pkg('MyPref')); }

eval { pkg('MyPref')->get('bogus_flow') };
like($@, qr/invalid/i);

my $old = pkg('MyPref')->get('search_page_size') || 'NULL';
my $new = rand(100);
pkg('MyPref')->set('search_page_size' => $new);
is(pkg('MyPref')->get('search_page_size'), $new);
pkg('MyPref')->set('search_page_size' => $old);
is(pkg('MyPref')->get('search_page_size'), $old);

