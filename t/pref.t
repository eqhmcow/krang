use strict;
use warnings;
use Krang::Script;
use Test::More qw(no_plan);

BEGIN { use_ok('Krang::Pref'); }

ok(Krang::Pref->get('search_page_size'));

my %contrib = Krang::Pref->get('contrib_type');
ok(keys(%contrib));
for (keys(%contrib)) {
    like($_, qr/^\d+$/);
    ok(length($contrib{$_}));
}

eval { Krang::Pref->get('bogus_flow') };
like($@, qr/invalid/i);

my $old = Krang::Pref->get('search_page_size');
my $new = rand(100);
Krang::Pref->set('search_page_size' => $new);
is(Krang::Pref->get('search_page_size'), $new);
Krang::Pref->set('search_page_size' => $old);
is(Krang::Pref->get('search_page_size'), $old);

my %old = Krang::Pref->get('contrib_type');
my %new = (1 => 'One', 2 => 'Two', 3 => 'Three');
Krang::Pref->set('contrib_type', %new);
is_deeply({Krang::Pref->get('contrib_type')}, \%new);
Krang::Pref->set('contrib_type', %old);
is_deeply({Krang::Pref->get('contrib_type')}, \%old);

