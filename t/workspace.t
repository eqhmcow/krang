use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;
use Krang::Site;
use Krang::Category;
use Krang::Conf qw(InstanceElementSet);

# use the TestSet1 instance, if there is one
foreach my $instance (Krang::Conf->instances) {
    Krang::Conf->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

BEGIN { use_ok('Krang::Workspace') }

# create a site and some categories to put stories in
my $site = Krang::Site->new(preview_url  => 'storytest.preview.com',
                            url          => 'storytest.com',
                            publish_path => '/tmp/storytest_publish',
                            preview_path => '/tmp/storytest_preview');
isa_ok($site, 'Krang::Site');
$site->save();
END { $site->delete() }
my ($root_cat) = Krang::Category->find(site_id => $site->site_id, dir => "/");
isa_ok($root_cat, 'Krang::Category');
$root_cat->save();

my @cat;
for (0 .. 10) {
    push @cat, Krang::Category->new(site_id   => $site->site_id,
                                    parent_id => $root_cat->category_id,
                                    dir       => 'test_' . $_);
    $cat[-1]->save();
}

# cleanup the mess
END {
    $_->delete for @cat;
}

SKIP: {
    skip('Story tests only work for TestSet1', 1)
      unless (InstanceElementSet eq 'TestSet1');

    # create 10 stories
    my @stories;
    for my $n (0 .. 9) {
        my $story = Krang::Story->new(categories => [$cat[$n]],
                                      title      => "Test$n",
                                      slug       => "test$n",
                                      class      => "article");
        $story->save();
        push(@stories, $story);
    }
    END { $_->delete for @stories }

    # test workspace find with just categories
    my @work = Krang::Workspace->find();
    ok(not grep { not defined $_ } @work);
    foreach my $story (@stories) {
        ok(grep { ref $_ eq 'Krang::Story' and
                    $_->story_id == $story->story_id } @work);
    }
          
    # checkin a story and make sure it's gone from workspace
    $stories[0]->checkin;
    @work = Krang::Workspace->find();
    ok(not grep { ref $_ eq 'Krang::Story' and
                    $_->story_id == $stories[0]->story_id } @work);
};

