use strict;
use warnings;

use Carp qw(croak);
use Data::Dumper;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile);
use IPC::Run qw(run);

BEGIN {
    # check for Bricolage environment vars
    eval "use Test::More skip_all => 'Bricolage vars not defined.'"
      unless ((grep {defined $ENV{"BRICOLAGE_$_"}}
               (qw/PASSWORD ROOT SERVER USERNAME/)) == 4 ? 1 : 0);

    ##### Running Bric Check #####
    $_ = catdir($ENV{BRICOLAGE_ROOT}, "lib");
    unshift(@INC, $ENV{PERL5LIB} = defined $ENV{PERL5LIB} ?
            "$ENV{PERL5LIB}:$_" : $_) if -e $_;

    # make sure Bric is found
    eval "use Bric";
    die "Cannot Load Bricolage: $@." if $@;

    use Bric::Config qw(:apachectl);

    # assume it's running if the pid_file is present, can't call kill do verify
    # if we don't own the process :(.
    eval "use Test::More skip_all => 'Bricolage is not running';"
      unless -e PID_FILE;
    ##### Running Bric Check #####

    # create lasistes element set
    my $root = $ENV{KRANG_ROOT};
    my $set = 'lasites';
    # will pull from Bric directly once something is modified to create a
    # category element
    my $xml = catfile($root, 't', 'bricloader', 'laelements.xml');

    my @command = (catfile($root, "bin", "krang_bric_eloader"),
                   "--set" => $set,
                   "--xml" => $xml,
                  );
    my $in;
    run(\@command, \$in, \*STDOUT, \*STDERR)
      or eval "use Test::More skip_all => 'Unable to run ".
        catfile($root, "bin", "krang_bric_eloader"). "';";

    END {
        # remove created element_lib
        my $path = catdir($root, 'element_lib', $set);
        rmtree([$path]) if -e $path;
    }

    # use bogus krang.conf
    $ENV{KRANG_CONF} = catfile($root, 't', 'bricloader', 'junk.conf');
}

use Test::More qw(no_plan);

use Krang::Script;
use Krang::Conf qw(KrangRoot InstanceElementSet);
use Krang::DataSet;
use Krang::ElementLibrary;


BEGIN {
    use_ok('Krang::BricLoader::DataSet');
    use_ok('Krang::BricLoader::Category');
    use_ok('Krang::BricLoader::Media');
    use_ok('Krang::BricLoader::Site');
    use_ok('Krang::BricLoader::Story');
}


# instantiate a DataSet
my $set = Krang::BricLoader::DataSet->new();
isa_ok($set, 'Krang::BricLoader::DataSet');

my (@categories, @media, @sites, @stories);
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


# add media
my $media_path = catfile(KrangRoot, 't', 'bricloader', 'lamedia.xml');
eval {@media = Krang::BricLoader::Media->new(path => $media_path);};
is($@, '', 'Media constructor did not croak :)');
$set->add(object => $_) for @media;


# add some stories
my $story_path = catfile(KrangRoot, 't', 'bricloader', 'lastories.xml');
eval {@stories = Krang::BricLoader::Story->new(path => $story_path);};
is($@, '', 'Story constructor did not croak :)');
$set->add(object => $_) for @stories;


# write output
my $kds = catfile(KrangRoot, 'tmp', 'bob.kds');
$set->write(path => $kds);

END {unlink($kds);}

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
    my $media = scalar @media;
    my $sites = scalar @sites;
    my $stories = scalar @stories;
    my $sum = $stories + $sites + $media + $categories;
    is(scalar @objects, $sum, 'Verify dataset object count');

    # import test
    $iset->import_all;
    is((grep {$_->isa('Krang::Site')} @imported), $sites,
       'Verified imported Site count');
    is((grep {$_->isa('Krang::Category')} @imported), $categories,
       'Verified imported Category count');
    is((grep {$_->isa('Krang::Media')} @imported), $media,
       'Verified imported Media count');
    is((grep {$_->isa('Krang::Story')} @imported), $stories,
       'Verified imported Story count');

    END {
        $_->delete for (grep {$_->isa('Krang::Story')} @imported);
        $_->delete for (grep {$_->isa('Krang::Media')} @imported);
        $_->delete for (grep {$_->isa('Krang::Category') && $_->dir ne '/'}
                        @imported);
        $_->delete for (grep {$_->isa('Krang::Site')} @imported);
    }
};

croak $@ if $@;
