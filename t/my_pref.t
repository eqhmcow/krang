use strict;
use warnings;
use Krang::Script;
use Test::More qw(no_plan);

BEGIN { use_ok('Krang::MyPref'); }

eval { Krang::MyPref->get('bogus_flow') };
like($@, qr/invalid/i);

my $old = Krang::MyPref->get('search_page_size') || 'NULL';
my $new = rand(100);
Krang::MyPref->set('search_page_size' => $new);
is(Krang::MyPref->get('search_page_size'), $new);
Krang::MyPref->set('search_page_size' => $old);
is(Krang::MyPref->get('search_page_size'), $old);

