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

my (@categories, @sites, @stories);
my $sites_path = catfile(KrangRoot, 't', 'bricloader', 'sites.xml');

eval {@sites = Krang::BricLoader::Site->new(path => $sites_path);};
is($@, '', 'Site constructor did not croak :)');

# add sites to data set
$set->add(object => $_) for @sites;


# let's do some categories
my $cat_path = catfile(KrangRoot, 't', 'bricloader', 'categories.xml');
eval {@categories = Krang::BricLoader::Category->new(path => $cat_path);};
is($@, '', 'Category constructor did not croak :)');

# add categories to data set
$set->add(object => $_) for @categories;


# add some stories
my $story_path = catfile(KrangRoot, 't', 'bricloader', 'lastories.xml');
eval {@stories = Krang::BricLoader::Story->new(path => $story_path);};
is($@, '', 'Story constructor did not croak :)');
$set->add(object => $_) for @stories;


# write output
my $kds = catfile(KrangRoot, 'tmp', 'bob.kds');
$set->write(path => $kds);


# validate output
eval {
    my @imported;
    my $iset = Krang::DataSet->new(path => $kds,
                                   import_callback =>
                                   sub {push @imported, $_[1]});
    isa_ok($iset, 'Krang::DataSet');

    # verify object count
    my @objects = $iset->list;
    my $categories = scalar @categories;
    my $sites = scalar @sites;
    my $stories = scalar @stories;
    my $sum = $stories + $sites + $categories;
    is(scalar @objects, $sum, 'Verify dataset object count');

    # import test
#    $iset->import_all;
#    is((grep {$_->isa('Krang::Site')} @imported), $sites,
#       'Verified imported Site count');
#    is((grep {$_->isa('Krang::Category')} @imported), $categories,
#       'Verified imported Category count');
#    is((grep {$_->isa('Krang::Story')} @imported), $stories,
#       'Verified imported Story count');
#    END {
#        $_->delete for (grep {$_->isa('Krang::Story')} @imported);
#        $_->delete for (grep {$_->isa('Krang::Category') && $_->dir ne '/'}
#                        @imported);
#        $_->delete for (grep {$_->isa('Krang::Site')} @imported);
#    }
};

croak $@ if $@;


END {
    unlink($kds);
}

__END__



