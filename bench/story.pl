use strict;
use warnings;
use Krang::Script;
use Krang::Benchmark qw(run_benchmark);
use Krang::Category;
use Krang::Site;
use Krang::Story;

my $count = 500;

# create a site and some categories to put stories in
my $site = Krang::Site->new(preview_url  => 'storybench.preview.com',
                            url          => 'storybench.com',
                            publish_path => '/tmp/storybench_publish',
                            preview_path => '/tmp/storybench_preview');
$site->save();
my ($root_cat) = Krang::Category->find(site_id => $site->site_id, dir => "/");
$root_cat->save();

my @cat;
for (0 .. 10) {
    push @cat, Krang::Category->new(site_id   => $site->site_id,
                                    parent_id => $root_cat->category_id,
                                    dir       => 'bench_' . $_);
    $cat[-1]->save();
}

# cleanup the mess
END { $site->delete()     }
END { $_->delete for @cat }



#############################################################################

my $i = 0;
my @stories;
run_benchmark(module => 'Krang::Story',
              name   => 'new, save empty',
              count  => $count,               
              code   =>
sub {
    # create a new story
    my $story = Krang::Story->new(categories => [$cat[0], $cat[1]],
                                  title      => "bench$i",
                                  slug       => "bench$i",
                                  class      => "article");
    $story->save();
    push(@stories, $story);
    $i++;
} );


#############################################################################

run_benchmark(module => 'Krang::Story',
              name   => 'new, save w/ content',
              count  => $count,               
              code   =>
sub {
    # create a new story
    my $story = Krang::Story->new(categories=> [$cat[int(rand(scalar(@cat)))]],
                                  title      => "bench$i",
                                  slug       => "bench$i",
                                  class      => "article");
    # add some content
    my $element = $story->element;
    $element->child('deck')->data('DECK DECK DECK');

    # add 10 paragraphs to 3 pages
    $element->add_child(class => 'page');
    $element->add_child(class => 'page');
    foreach my $page ($element->match('/page')) {
        for my $x (1 .. 10) {
            $page->add_child(class => "paragraph", data => "bla$x "x40);
        }
    }

    $story->save();
    push(@stories, $story);
    $i++;
} );


#############################################################################

$i = 0;
run_benchmark(module => 'Krang::Story',
              name   => 'find by story ID',
              count  => scalar @stories,
              code   =>
sub {
    my ($cat) = Krang::Story->find(story_id => $stories[($i % scalar(@stories))]->story_id);
    $i++;
} );

#############################################################################

$i = 0;
run_benchmark(module => 'Krang::Story',
              name   => 'find by category ID',
              count  => scalar(@stories) / 20,
              code   =>
sub {
    my ($cat) = Krang::Story->find(category_id => $cat[($i % scalar(@cat))]->category_id);
    $i++;
} );


#############################################################################

$i = 0;
run_benchmark(module => 'Krang::Story',
              name   => 'find by URL',
              count  => scalar @stories,
              code   =>
sub {
    my ($cat) = Krang::Story->find(url => $stories[($i % scalar(@stories))]->url);
    $i++;
} );


#############################################################################

run_benchmark(module => 'Krang::Story',
              name   => 'find all, limit 20',
              count  => $count / 10,
              code   =>
sub {
    my @s = Krang::Story->find(limit => 20);
} );


#############################################################################

run_benchmark(module => 'Krang::Story',
              name   => 'delete',
              count  => scalar @stories,
              code   =>
sub {
    my $story = pop @stories;
    $story->delete;
} );

