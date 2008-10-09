use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Test::More qw(no_plan);

BEGIN { use_ok(pkg('Pref')); }

ok(pkg('Pref')->get('search_page_size'));

my %contrib = pkg('Pref')->get('contrib_type');
ok(keys(%contrib));
for (keys(%contrib)) {
    like($_, qr/^\d+$/);
    ok(length($contrib{$_}));
}

eval { pkg('Pref')->get('bogus_flow') };
like($@, qr/invalid/i);

my $old = pkg('Pref')->get('search_page_size');
my $new = rand(100);
pkg('Pref')->set('search_page_size' => $new);
is(pkg('Pref')->get('search_page_size'), $new);
pkg('Pref')->set('search_page_size' => $old);
is(pkg('Pref')->get('search_page_size'), $old);

my %old = pkg('Pref')->get('contrib_type');
my %new = (1 => 'One', 2 => 'Two', 3 => 'Three');
pkg('Pref')->set('contrib_type', %new);
is_deeply({pkg('Pref')->get('contrib_type')}, \%new);
pkg('Pref')->set('contrib_type', %old);
is_deeply({pkg('Pref')->get('contrib_type')}, \%old);

# test language setting
$old = pkg('Pref')->get('language') || 'en';
$new = 'i-klingon';
ok(pkg('Pref')->set('language' => $new), "Setting language pref to '$new'");
is(pkg('Pref')->get('language'), $new, 'Getting language preference after setting it');
ok(pkg('Pref')->set('language' => $old), "Setting language pref to '$old'");
is(pkg('Pref')->get('language'), $old, 'Getting language preference after setting it');

