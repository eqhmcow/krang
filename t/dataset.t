use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;
use Krang::Site;
use Krang::Category;
use Krang::Story;
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);
BEGIN { use_ok('Krang::DataSet') }

my $DEBUG = 1; # supresses deleting kds files at process end

# create a site and category for dummy story
my $site = Krang::Site->new(preview_url  => 'storytest.preview.com',
                            url          => 'storytest.com',
                            publish_path => '/tmp/storytest_publish',
                            preview_path => '/tmp/storytest_preview');
$site->save();
END { $site->delete() }
my ($category) = Krang::Category->find(site_id => $site->site_id());

# create a new story
my $story = Krang::Story->new(categories => [$category],
                              title      => "Test",
                              slug       => "test",
                              class      => "article");
$story->save();
END { $story->delete() }

# create a new story, again
my $story2 = Krang::Story->new(categories => [$category],
                               title      => "Test2",
                               slug       => "test2",
                               class      => "article");
$story2->save();
END { $story2->delete() }

# create a data set containing the story
my $set = Krang::DataSet->new();
isa_ok($set, 'Krang::DataSet');
$set->add(object => $story);
$set->add(object => $story2);

# write it out
my $path = catfile(KrangRoot, 'tmp', 'test.kds');
$set->write(path => $path);
ok(-e $path and -s $path);
END { unlink($path) if -e $path and not $DEBUG };

# try loading it again
my $loaded = Krang::DataSet->new(path => $path);
isa_ok($loaded, 'Krang::DataSet');

# make sure add() matches loaded
my @objects = $loaded->list();
ok(@objects >= 2);
ok(grep { $_->[0] eq 'Krang::Story' and
          $_->[1] eq $story->story_id  } @objects);
ok(grep { $_->[0] eq 'Krang::Story' and
          $_->[1] eq $story2->story_id } @objects);

# see if it will write again
my $path2 = catfile(KrangRoot, 'tmp', 'test2.kds');
$set->write(path => $path2);
ok(-e $path2 and -s $path2);
END { unlink($path2) if -e $path2 and not $DEBUG };

# create 25 stories
my $count = Krang::Story->find(count => 1);
my $undo = catfile(KrangRoot, 'tmp', 'undo.pl');
system("bin/krang_floodfill --stories 20 --sites 1 --cats 5 --templates 0 --media 5 --users 0 --covers 5 --undo_script $undo 2&>1 /dev/null");
END { system("$undo 2&>1 /dev/null"); }
is(Krang::Story->find(count => 1), $count + 25);

# see if we can serialize them
my @stories = Krang::Story->find(limit    => 25, 
                                 offset   => $count, 
                                 order_by => 'story_id');

# create a data set containing the story
my $set25 = Krang::DataSet->new();
isa_ok($set25, 'Krang::DataSet');
$set25->add(object => $_) for @stories;

my $path25 = catfile(KrangRoot, 'tmp', '25stories.kds');
$set25->write(path => $path25);
ok(-e $path25 and -s $path25);
END { unlink($path25) if -e $path25 and not $DEBUG };
