use warnings;

use File::Spec::Functions qw(catfile);

BEGIN {
    my $root = $ENV{KRANG_ROOT};

    # load CanoeKayak elementset w/bogus conf
    $ENV{KRANG_CONF} = catfile($root, 't', 'CanoeKayak', 'krang.conf');
}

use Test::More qw(no_plan);

use Krang::Script;

use Krang::Conf qw(KrangRoot);
use Krang::DataSet;

# Object Count
use constant CATEGORIES => 9;
use constant MEDIA	=> 5;
use constant SITES	=> 1;
use constant STORIES	=> 8;
use constant TEMPLATES	=> 36;

my @imported;
my $path = catfile(KrangRoot, 't', 'CanoeKayak', 'CanoeKayak.kds');
my $kds = Krang::DataSet->new(path => $path,
                              import_callback => sub {push @imported, $_[1]});
eval {$kds->import_all;};
is($@, '', 'No import eval errors');

# Verify Object counts...
our($category_count, $media_count, $site_count, $story_count, $template_count);
for my $c(qw/Category Media Site Story Template/) {
    my $var = lc $c . "_count";
    $$var = grep {$_->isa("Krang::$c")} @imported;
}

is($site_count, SITES, 'Verified Sites Count');
is($category_count, CATEGORIES, 'Verified Categories Count');
is($media_count, MEDIA, 'Verified Media Count');
is($story_count, STORIES, 'Verified Stories Count');
is($template_count, TEMPLATES, 'Verified Templates Count');


# cleanup everything in the right order
END {
    $_->delete for (grep { $_->isa('Krang::Media') } @imported);
    $_->delete for (grep { $_->isa('Krang::Story') } @imported);
    $_->delete
      for (sort { length($b->url) cmp length($a->url) }
           grep { defined $_->parent_id }
           grep { $_->isa('Krang::Category') } @imported);
    $_->delete for (grep { $_->isa('Krang::Site') } @imported);
    $_->delete for (grep { $_->isa('Krang::Contrib') } @imported);
};
