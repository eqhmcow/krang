use strict;
use warnings;

use Carp qw(croak);
use Config::ApacheFormat;
use Data::Dumper;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile);
use IO::File;
use IPC::Run qw(run);

BEGIN {
    # check for Bricolage environment vars
    for (qw/PASSWORD ROOT SERVER USERNAME/) {
        my $var = "BRICOLAGE_$_";
        eval "use Test::More skip_all => '$var is not defined.'"
          unless exists $ENV{$var};
    }

    ##### Running Bric Check #####
    # make sure we've got Bric
    unshift(@INC, catdir($ENV{BRICOLAGE_ROOT}, "lib"));
    eval "use Bric";
    eval "use Test::More skip_all => 'Cannot Load Bricolage'" if $@;

    # assume it's running if the pid_file is present, can't call kill do verify
    # if we don't own the process :(.
    my $conf = Config::ApacheFormat->new();
    $conf->read(catfile($ENV{BRICOLAGE_ROOT}, 'conf', 'httpd.conf'));
    eval "use Test::More skip_all => 'Bricolage is not running';"
      unless -e $conf->get("PidFile");
    ##### Running Bric Check #####

    # ElementSet has no Krang module dependecies...:)
    require Krang::BricLoader::ElementSet;
    my $root = $ENV{KRANG_ROOT};

    # Create ElementSet
    local $/ = undef;
    my $xml_doc = catfile($root, 't', 'bricloader', 'laelements.xml');
    my $rh = IO::File->new("<$xml_doc") or
      croak("Can't open '$xml_doc' for reading!");
    my $xml = <$rh>;
    $rh->close;
    eval {
        Krang::BricLoader::ElementSet->create(set => 'lasites', xml => $xml);
    };
    eval "use Test::More skip_all => 'ElementSet creation failed: $@'" if $@;

    END {
        # remove created element_lib
        my $path = catdir($root, 'element_lib', 'lasites');
        rmtree([$path]) if -e $path;
    }

    # set instance var
    $ENV{KRANG_INSTANCE} = 'lasites';

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
    use_ok('Krang::BricLoader::Contrib');
    use_ok('Krang::BricLoader::ElementSet');
    use_ok('Krang::BricLoader::Media');
    use_ok('Krang::BricLoader::Site');
    use_ok('Krang::BricLoader::Story');
    use_ok('Krang::BricLoader::Template');
}


# instantiate a DataSet
my $set = Krang::BricLoader::DataSet->new();
isa_ok($set, 'Krang::BricLoader::DataSet');

my (@categories, @media, @sites, @stories, @templates);

my $sites_path = catfile(KrangRoot, 't', 'bricloader', 'lasites.xml');
eval {@sites = Krang::BricLoader::Site->new(path => $sites_path);};
is($@, '', 'Site constructor did not croak :)');
$set->add(object => $_) for @sites;


# let's do some categories
my $cat_path = catfile(KrangRoot, 't', 'bricloader', 'lacategories.xml');
eval {@categories = Krang::BricLoader::Category->new(path => $cat_path);};
is($@, '', 'Category constructor did not croak :)');
$set->add(object => $_) for @categories;


# add media
my $media_path = catfile(KrangRoot, 't', 'bricloader', 'lamedia.xml');
eval {@media = Krang::BricLoader::Media->new(dataset => $set,
                                             path => $media_path);};
is($@, '', 'Media constructor did not croak :)');
$set->add(object => $_) for @media;


# add contributors
$set->add(object => $_) for Krang::BricLoader::Contrib->load;


# add templates
my $template_path = catfile(KrangRoot, 't', 'bricloader', 'latemplates.xml');
eval {@templates = Krang::BricLoader::Template->new(path => $template_path)};
is($@, '', 'Template constructor did not croak :)');
$set->add(object => $_) for @templates;


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
    # 1 on extra for the category added via add_new_path :)
    my $categories = scalar @categories + 1;
    my $contributors = Krang::BricLoader::Contrib->get_contrib_count;
    my $media = scalar @media;
    my $sites = scalar @sites;
    my $stories = scalar @stories;
    my $templates = scalar @templates;
    my $sum = $templates + $stories + $sites + $media + $contributors
      + $categories;
    is(scalar @objects, $sum, 'Verify dataset object count');

    # import test
    $iset->import_all;
    is((grep {$_->isa('Krang::Site')} @imported), $sites,
       'Verified imported Site count');
    is((grep {$_->isa('Krang::Category')} @imported), $categories,
       'Verified imported Category count');
    is((grep {$_->isa('Krang::Contrib')} @imported), $contributors,
       'Verified imported Contributor count');
    is((grep {$_->isa('Krang::Media')} @imported), $media,
       'Verified imported Media count');
    is((grep {$_->isa('Krang::Story')} @imported), $stories,
       'Verified imported Story count');
    is((grep {$_->isa('Krang::Template')} @imported), $templates,
       'Verified imported Template count');

    END {
        $_->delete for (grep {$_->isa('Krang::Story')} @imported);
        $_->delete for (grep {$_->isa('Krang::Template')} @imported);
        $_->delete for (grep {$_->isa('Krang::Media')} @imported);
        $_->delete for (grep {$_->isa('Krang::Contrib')} @imported);
        $_->delete for (grep {$_->isa('Krang::Category') && $_->dir ne '/'}
                        @imported);
        $_->delete for (grep {$_->isa('Krang::Site')} @imported);
    }
};

croak $@ if $@;
