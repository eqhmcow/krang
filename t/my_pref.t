use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Test::More qw(no_plan);

BEGIN { use_ok(pkg('MyPref')); }

eval { pkg('MyPref')->get('bogus_flow') };
like($@, qr/invalid/i, "Invalid pref");

my $old = pkg('MyPref')->get('search_page_size') || 'NULL';
my $new = rand(100);
ok(pkg('MyPref')->set('search_page_size' => $new), "Setting my search_page_size pref to random value");
is(pkg('MyPref')->get('search_page_size'),  $new,  "Getting this value");
ok(pkg('MyPref')->set('search_page_size' => $old), "Resetting my search_page_size pref to its old value");
is(pkg('MyPref')->get('search_page_size'),  $old,  "Getting this value");

$old = pkg('MyPref')->get('language') || 'en';
$new = 'i-klingon';
ok(pkg('MyPref')->set('language' => $new), "Setting my language pref to '$new'");
is(pkg('MyPref')->get('language'), $new, "Getting language preference after setting it to '$new'");
ok(pkg('MyPref')->set('language' => $old), "Setting my language pref to '$old'");
is(pkg('MyPref')->get('language'), $old, "Getting language preference after resetting it to $old");
