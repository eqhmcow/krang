use strict;
use warnings;
use Krang::Script;
use Krang::Benchmark qw(run_benchmark);
use Krang::Category;
use Krang::Site;

my $count = 500;

# set up a $count/100 sites to use for testing
my @sites;
my @cats;
for (0 .. int($count/100)) {
    my $site = Krang::Site->new(preview_path => "/tmp/bench_site_preview_$_",
                                preview_url => "preview.bench_site_$_.com",
                                publish_path => "/tmp/bench_site_publish_$_",
                                url          => "bench_site_$_.com");
    $site->save();
    push(@sites, $site);

    # collect root categories
    push(@cats, Krang::Category->find(site_id => $site->site_id));
}
END { $_->delete() for @sites };



#############################################################################

my $i = 0;
run_benchmark(module => 'Krang::Category',
              name   => 'new, save',
              count  => $count,               
              code   =>
sub {
    my $parent_cat = $cats[int(rand(scalar(@cats)))];
    my $cat = Krang::Category->new(dir       => "cat_$i",
                                   parent_id => $parent_cat->category_id);
    $i++;
    $cat->save();
    push(@cats, $cat);
} );

#############################################################################

$i = 0;
run_benchmark(module => 'Krang::Category',
              name   => 'find by ID',
              count  => $count * 5,
              code   =>
sub {
    my ($cat) = Krang::Category->find(category_id => $cats[($i % scalar(@cats))]->category_id);
    $i++;
} );


#############################################################################

$i = 0;
run_benchmark(module => 'Krang::Category',
              name   => 'find by URL',
              count  => $count * 5,
              code   =>
sub {
    my ($cat) = Krang::Category->find(url => $cats[($i % scalar(@cats))]->url);
    $i++;
} );


#############################################################################

run_benchmark(module => 'Krang::Category',
              name   => 'find all, limit 20',
              count  => $count / 10,
              code   =>
sub {
    my @cats = Krang::Category->find(limit => 20);
} );


#############################################################################

run_benchmark(module => 'Krang::Category',
              name   => 'delete',
              count  => $count,
              code   =>
sub {
    my $cat = pop @cats;
    $cat->delete;
} );

