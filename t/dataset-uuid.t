# tests for the UUID-matching features of Krang::DataSet

use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'Media';
use Krang::ClassLoader 'Template';
use Krang::ClassLoader 'User';
use Krang::ClassLoader 'Group';
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
my $site = pkg('Site')->new(
    preview_url  => 'storytest.preview.com',
    url          => 'storytest.com',
    publish_path => '/tmp/storytest_publish',
    preview_path => '/tmp/storytest_preview'
);
$site->save();
END { $site->delete() }
my ($category) = pkg('Category')->find(site_id => $site->site_id());

my $sub_cat = pkg('Category')->new(
    dir       => 'foo',
    parent_id => $category->category_id,
    site_id   => $site->site_id
);
$sub_cat->save();

END {
    (pkg('Category')->find(category_id => $sub_cat->category_id))[0]->delete;
}

my $site2 = pkg('Site')->new(
    preview_url  => 'storytest2.preview.com',
    url          => 'storytest2.com',
    publish_path => '/tmp/storytest_publish2',
    preview_path => '/tmp/storytest_preview2'
);
$site2->save();
END { $site2->delete() }
my ($category2) = pkg('Category')->find(site_id => $site2->site_id());

my $site3 = pkg('Site')->new(
    preview_url  => 'storytest3.preview.com',
    url          => 'storytest3.com',
    publish_path => '/tmp/storytest_publish3',
    preview_path => '/tmp/storytest_preview3'
);
$site3->save();
END { $site3->delete() }
my ($category3) = pkg('Category')->find(site_id => $site3->site_id());

# create a new story
my $story;
eval {
    $story = pkg('Story')->new(
        categories => [$category],
        title      => "Test",
        slug       => "test",
        class      => "article"
    );
};

# Was story creation successful?
if ($@) {
    if ($@ =~ qr/Unable to find top-level element named 'article'/) {

        # Story type "article" doesn't exist in this set.  Exit test now.
      SKIP: {
            skip("Unable to find top-level element named 'article' in element lib");
        }
        exit(0);
    } else {

        # We've encountered some other unexpected error.  Re-throw.
        die($@);
    }
}

$story->save();
END { (pkg('Story')->find(story_id => $story->story_id))[0]->delete() }

# create a test media object
my $media = pkg('Media')->new(
    title         => 'test media object',
    category_id   => $category->category_id,
    media_type_id => 1
);
my $filepath = catfile(KrangRoot, 't', 'media', 'krang.jpg');
my $fh = new FileHandle $filepath;
$media->upload_file(filename => 'krang.jpg', filehandle => $fh);
$media->save();
END { (pkg('Media')->find(media_id => $media->media_id))[0]->delete() }

# create a test template
my $template = pkg('Template')->new(
    category => $category,
    content  => '<blink><tmpl_var bob></blink>',
    filename => 'bob.tmpl'
);
$template->save();
END { $template->delete() }

# create a test group
my $group = pkg('Group')->new(name => 'testing_group');
$group->save;
END { $group->delete }

# create a test user
my $user = pkg('User')->new(
    login    => 'testing',
    password => 'dataset!'
);
$user->group_ids_push($group->group_id);
$user->save();

END {
    dbh()->do('DELETE FROM old_password WHERE user_id = ?', {}, $user->user_id);
    $user->delete;
}

# create a data set containing the story and media
my $set = pkg('DataSet')->new();
isa_ok($set, 'Krang::DataSet');
$set->add(object => $story);
$set->add(object => $media);
$set->add(object => $template);
$set->add(object => $site3);
$set->add(object => $sub_cat);
$set->add(object => $user);

# write it out
my $path = catfile(KrangRoot, 'tmp', 'test.kds');
$set->write(path => $path);
ok(-e $path and -s $path);
END { unlink($path) if ($path and -e $path) }

# try moving the objects and then re-importing - UUID match should
# move them back
{
    my $old_url = $story->url;
    $story->categories([$category2]);
    $story->save();
    my $new_url = $story->url;
    isnt($old_url, $new_url, "URL changed");

    my $old_media_url = $media->url;
    $media->category_id($category2->category_id);
    $media->save();
    my $new_media_url = $media->url;
    isnt($old_media_url, $new_media_url, "media URL changed");

    my $old_template_url = $template->url;
    $template->category_id($category2->category_id);
    $template->save();
    my $new_template_url = $template->url;
    isnt($old_template_url, $new_template_url, "template URL changed");

    my $old_site_url = $site3->url;
    $site3->url("new.example.com");
    $site3->save();
    my $new_site_url = $site3->url;
    isnt($old_site_url, $new_site_url, "site URL changed");

    my $old_cat_url = $sub_cat->url;
    $sub_cat->dir("bar");
    $sub_cat->save();
    my $new_cat_url = $sub_cat->url;
    isnt($old_cat_url, $new_cat_url, "category URL changed");

    my $old_login = $user->login;
    $user->login('testing2');
    $user->save();
    my $new_login = $user->login;
    isnt($old_login, $new_login, "user login changed");

    my $old_name = $group->name;
    $group->name('testing2');
    $group->save();
    my $new_name = $group->name;
    isnt($old_name, $new_name, "group name changed");

    pkg('DataSet')->new(path => $path)->import_all();

    my ($found) = pkg('Story')->find(story_id => $story->story_id);
    is($found->url, $old_url);

    my ($found2) = pkg('Media')->find(media_id => $media->media_id);
    is($found2->url, $old_media_url);

    my ($found3) = pkg('Template')->find(template_id => $template->template_id);
    is($found3->url, $old_template_url);

    my ($found_site) = pkg('Site')->find(site_id => $site3->site_id);
    is($found_site->url, $old_site_url, "Site reverted to old URL");

    my ($found_cat) = pkg('Category')->find(category_id => $sub_cat->category_id);
    is($found_cat->url, $old_cat_url, "Category reverted to old URL");

    my ($found_user) = pkg('User')->find(user_id => $user->user_id);
    is($found_user->login, $old_login, "User reverted to old login");

    my ($found_group) = pkg('Group')->find(group_id => $group->group_id);
    is($found_group->name, $old_name, "Group reverted to old name");
}

# try an import with UUID matching off - should create copies
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
    my ($found) = pkg('Story')->find(story_id => $s->story_id);
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

    dbh()->do(
        'UPDATE story SET story_uuid = ? WHERE story_id = ?',
        undef, '98DBE9EE-684A-11DB-8805-80D0EC6873C7',
        $story->story_id
    );

    eval { pkg('DataSet')->new(path => $path)->import_all(uuid_only => 1); };
    ok($@);
    isa_ok($@, 'Krang::DataSet::ImportRejected');
    like($@->message, qr/primary url.*already exists/);
}

