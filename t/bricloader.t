use strict;
use warnings;

use Carp qw(croak);
use Data::Dumper;
use File::Spec::Functions qw(catfile);
use Test::More qw(no_plan);

use Krang::Script;
use Krang::Conf qw(KrangRoot);
use Krang::DataSet;

BEGIN {
    use_ok('Krang::BricLoader::DataSet');
    use_ok('Krang::BricLoader::Category');
    use_ok('Krang::BricLoader::Site');
    use_ok('Krang::BricLoader::Story');
}

# instantiate a DataSet
my $set = Krang::BricLoader::DataSet->new();
isa_ok($set, 'Krang::BricLoader::DataSet');

my (@categories, @sites);
my $sites_path = catfile(KrangRoot, 't', 'bricloader', 'sites.xml');

eval {@sites = Krang::BricLoader::Site->new(path => $sites_path);};
is($@, '', 'Site constructor succeeded :)');

# check for valid site objects
isa_ok($_, 'Krang::BricLoader::Site') for @sites;

# add sites to data set
$set->add(object => $_) for @sites;

# let's do some categories
my $cat_path = catfile(KrangRoot, 't', 'bricloader', 'categories.xml');
eval {@categories = Krang::BricLoader::Category->new(path => $cat_path);};
is($@, '', 'Category constructor succeeded :)');

# add categories to data set
for (@categories) {
    eval {$set->add(object => $_)};
    is($@, '', 'Category addition succeeded :)');
    if ($@) {
        print STDERR "\n\n", $@;
        exit 1;
    }
}

# write output
my $kds = catfile(KrangRoot, 'tmp', 'bob.kds');
$set->write(path => $kds);

# validate output
eval {
    my $iset = Krang::DataSet->new(path => $kds);
    isa_ok($iset, 'Krang::DataSet');
    # verify object count
    my @objects = $iset->list;
    my $sum = scalar @sites + scalar @categories;
    is(scalar @objects, $sum, 'Verify dataset object count');
};
croak $@ if $@;

END {
    unlink($kds);
}
