use strict;
use warnings;

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

my @sites;
my $sites_path = catfile(KrangRoot, 't', 'bricloader', 'sites.xml');

eval {@sites = Krang::BricLoader::Site->new(path => $sites_path);};
if ($@) {
    # DEBUG
    print STDERR "\nKrang::BricLoader::Site constructor failed:\n",
      Data::Dumper->Dump([$@->errors],['errors']), "\n\n";
    croak $@;
}

# check for valid site objects
isa_ok($_, 'Krang::BricLoader::Site') for @sites;

# add sites to data set
for (@sites) {
    $set->add(object => $_);
}

# write output
my $kds = catfile(KrangRoot, 'tmp', 'bob.kds');
$set->write(path => $kds);

# validate output
eval {
    my $iset = Krang::DataSet->new(path => $kds);
    isa_ok($iset, 'Krang::DataSet');
};
croak $@ if $@;

END {
    unlink($kds);
}
