# tests for the UUID-matching features of Krang::DataSet

use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'DataSet';
use Krang::ClassLoader Conf    => qw(KrangRoot InstanceElementSet);
use Krang::ClassLoader Element => qw(foreach_element);
use Krang::ClassLoader DB      => qw(dbh);
use File::Spec::Functions qw(catfile);

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

# create a site and category for dummy story
my $site = pkg('Site')->new(preview_url  => 'storytest.preview.com',
                            url          => 'storytest.com',
                            publish_path => '/tmp/storytest_publish',
                            preview_path => '/tmp/storytest_preview');
$site->save();
END { $site->delete() }
my ($category) = pkg('Category')->find(site_id => $site->site_id());

my $site2 = pkg('Site')->new(preview_url  => 'storytest2.preview.com',
                             url          => 'storytest2.com',
                             publish_path => '/tmp/storytest_publish2',
                             preview_path => '/tmp/storytest_preview2');
$site2->save();
END { $site2->delete() }
my ($category2) = pkg('Category')->find(site_id => $site2->site_id());

# create a new story
my $story;
eval {
    $story = pkg('Story')->new(categories => [$category],
                               title      => "Test",
                               slug       => "test",
                               class      => "article");
};

# Was story creation successful?
if ($@) {
    if ($@ =~ qr/Unable to find top-level element named 'article'/) {

        # Story type "article" doesn't exist in this set.  Exit test now.
      SKIP: {
            skip(
"Unable to find top-level element named 'article' in element lib");
        }
        exit(0);
    } else {

        # We've encountered some other unexpected error.  Re-throw.
        die($@);
    }
}

$story->save();
END { (pkg('Story')->find(story_id => $story->story_id))[0]->delete() }

# create a data set containing the story
my $set = pkg('DataSet')->new();
isa_ok($set, 'Krang::DataSet');
$set->add(object => $story);

# write it out
my $path = catfile(KrangRoot, 'tmp', 'test.kds');
$set->write(path => $path);
ok(-e $path and -s $path);
END { unlink($path) if ($path and -e $path) }

# try moving the story and then re-importing - UUID match should move
# the story back
{
    my $old_url = $story->url;
    $story->categories([$category2]);
    $story->save();
    my $new_url = $story->url;
    isnt($old_url, $new_url, "URL changed");

    pkg('DataSet')->new(path => $path)->import_all();

    my ($found) = Krang::Story->find(story_id => $story->story_id);
    is($found->url, $old_url);
}

# try an import with UUID matching off - should create a copy of the story
{
    my ($s) = pkg('Story')->find(story_id => $story->story_id);
    my $old_url = $s->url;
    $s->categories([$category2]);
    $s->checkout();
    $s->save();
    my $new_url = $s->url;
    isnt($old_url, $new_url, "URL changed");

    pkg('DataSet')->new(path => $path)->import_all(no_uuid => 1);

    # the original story is unchanged
    my ($found) = Krang::Story->find(story_id => $s->story_id);
    is($found->url, $new_url);

    # find the new one
    my ($new) = pkg('Story')->find(url => $old_url);
    isnt($new->story_id, $s->story_id);
    $new->delete;
}

# try an import with UUID matching required after changing the UUID
# and resetting to old URL - should blow up with a URL violation
{
    my ($s) = pkg('Story')->find(story_id => $story->story_id);
    my $old_url = $s->url;
    $s->categories([$category]);
    $s->checkout();
    $s->save();
    my $new_url = $s->url;
    isnt($old_url, $new_url, "URL changed");

    dbh()->do('UPDATE story SET story_uuid = ? WHERE story_id = ?',
              undef, '98DBE9EE-684A-11DB-8805-80D0EC6873C7', $story->story_id
             );

    eval { 
        pkg('DataSet')->new(path => $path)->import_all(uuid_only => 1);
    };
    ok($@);
    isa_ok($@, 'Krang::DataSet::ImportRejected');
    like($@->message, qr/primary url.*already exists/);
}

