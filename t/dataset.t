use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader Conf    => qw(KrangRoot InstanceElementSet);
use Krang::ClassLoader Element => qw(foreach_element);
use File::Spec::Functions qw(catfile);

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

BEGIN { use_ok(pkg('DataSet')) }

my $STORY_DELETE = 1;    # If set to 0, surpressed END{} delete functions.
my $DEBUG        = 0;    # supresses deleting kds files at process end

# try creating an empty dataset
my $empty = pkg('DataSet')->new();
isa_ok($empty, 'Krang::DataSet');

# test to make sure dataset can do everything it says it can.
can_ok($empty, ('find', 'add', 'list', 'write', 'import_all', 'map_id', 'register_id', 'map_file'));

my $empty_path = catfile(KrangRoot, 'tmp', 'empty.kds');
eval { $empty->write(path => $empty_path); };
like($@, qr/empty dataset/);

# create a dataset with a single contributor
my $contrib = pkg('Contrib')->new(
    first  => 'J.',
    middle => 'Jonah',
    last   => 'Jameson',
    email  => 'jjj@dailybugle.com',
    bio    => 'The editor of the Daily Bugle.',
);
$contrib->contrib_type_ids(1, 3);
$contrib->save();
END { $contrib->delete() }

my $cset = pkg('DataSet')->new();
isa_ok($cset, 'Krang::DataSet');
$cset->add(object => $contrib);

my $jpath = catfile(KrangRoot, 'tmp', 'jjj.kds');
$cset->write(path => $jpath);
ok(-e $jpath and -s $jpath);
END { unlink($jpath) if -e $jpath and not $DEBUG }

# try an import, should work
$cset->import_all();

# now try it compressed
my $lpath = catfile(KrangRoot, 'tmp', 'lll.kds.gz');
$cset->write(path => $lpath, compress => 1);
ok(-e $lpath and -s $lpath);
END { unlink($lpath) if -e $lpath and not $DEBUG }

# and make sure we can load it compressed
ok(my $lset = pkg('DataSet')->new(path => $lpath), 'create DataSet for compressed file');
$lset->import_all();

# try an import with no_update, should fail
eval { $cset->import_all(no_update => 1); };
isa_ok($@, 'Krang::DataSet::ImportRejected');

# make a change and see if it gets overwritten
$contrib->bio('The greatest editor of the Daily Bugle, ever.');
$contrib->save;

my ($loaded_contrib) = pkg('Contrib')->find(contrib_id => $contrib->contrib_id);
is($loaded_contrib->bio, 'The greatest editor of the Daily Bugle, ever.');

$cset->import_all();

my ($loaded_contrib2) = pkg('Contrib')->find(contrib_id => $contrib->contrib_id);
is($loaded_contrib2->bio, 'The editor of the Daily Bugle.');

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

my $site2 = pkg('Site')->new(
    preview_url  => 'storytest2.preview.com',
    url          => 'storytest2.com',
    publish_path => '/tmp/storytest_publish2',
    preview_path => '/tmp/storytest_preview2'
);
$site2->save();
END { $site2->delete() }
my ($category2) = pkg('Category')->find(site_id => $site2->site_id());

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
        $STORY_DELETE = 0;
      SKIP: { skip("Unable to find top-level element named 'article' in element lib"); }
        exit(0);
    } else {

        # We've encountered some other unexpected error.  Re-throw.
        die($@);
    }
}

$story->save();

END {
    (pkg('Story')->find(url => $story->url))[0]->delete()
      if $STORY_DELETE;
}

# create a new story, again
my $story2 = pkg('Story')->new(
    categories => [$category],
    title      => "Test2",
    slug       => "test2",
    class      => "article"
);
$story2->save();

END {
    (pkg('Story')->find(url => $story2->url))[0]->delete()
      if $STORY_DELETE;
}

# add schedule for story
my $sched = pkg('Schedule')->new(
    object_type => 'story',
    object_id   => $story->story_id,
    action      => 'publish',
    repeat      => 'hourly',
    minute      => '0'
);

# create a data set containing the story
my $set = pkg('DataSet')->new();
isa_ok($set, 'Krang::DataSet');
$set->add(object => $story);
$set->add(object => $story2);

# write it out
my $path = catfile(KrangRoot, 'tmp', 'test.kds');
$set->write(path => $path);
ok(-e $path and -s $path);
END { unlink($path) if ($path and -e $path) and not $DEBUG }

# try loading it again
my $loaded = pkg('DataSet')->new(path => $path);
isa_ok($loaded, 'Krang::DataSet');

# make sure add() matches loaded
my @objects = $loaded->list();
ok(@objects >= 2);
ok(grep { $_->[0]->isa('Krang::Story') and $_->[1] eq $story->story_id } @objects);
ok(grep { $_->[0]->isa('Krang::Story') and $_->[1] eq $story2->story_id } @objects);

# try an import
$loaded->import_all();

# try an import with no_update, should fail
eval { $loaded->import_all(no_update => 1); };
isa_ok($@, 'Krang::DataSet::ImportRejected');

# see if it will write again
my $path2 = catfile(KrangRoot, 'tmp', 'test2.kds');
$set->write(path => $path2);
ok(-e $path2 and -s $path2);
END { unlink($path2) if ($path2 and -e $path2) and not $DEBUG }

# create a media object
my $media =
  pkg('Media')
  ->new(title => 'test media object', category_id => $category->category_id, media_type_id => 1);
my $filepath = catfile(KrangRoot, 't', 'media', 'krang.jpg');
my $fh = new FileHandle $filepath;
$media->upload_file(filename => 'krang.jpg', filehandle => $fh);
$media->save();
END { $media->delete if $media }

# add it to the set
$loaded->add(object => $media);

# see if it will write again
my $path3 = catfile(KrangRoot, 'tmp', 'test3.kds');
$loaded->write(path => $path3);
ok(-e $path3 and -s $path3);
END { unlink($path3) if ($path3 and -e $path3) and not $DEBUG }

SKIP: {
    skip('floodfill tests only work for TestSet1 and Default', 1)
      unless (InstanceElementSet eq 'TestSet1'
        or InstanceElementSet eq 'Default');

    # create 10 stories
    my $count = pkg('Story')->find(count => 1);
    my $undo = catfile(KrangRoot, 'tmp', 'undo.pl');
    $ENV{KRANG_INSTANCE} = pkg('Conf')->instance;
    my $cmd = catfile(KrangRoot, 'bin', 'krang_floodfill');
    system(
        "$cmd --stories 7 --sites 1 --cats 3 --templates 0 --media 5 --users 0 --covers 3 --contribs 10 --undo_script $undo > /dev/null 2>&1"
    );
    is(pkg('Story')->find(count => 1), $count + 10);

    # see if we can serialize them
    my @stories = pkg('Story')->find(
        limit    => 10,
        offset   => $count,
        order_by => 'story_id'
    );

    my @story_uuids = map { $_->story_uuid } @stories;

    # create a data set containing the stories
    my $set10 = pkg('DataSet')->new();
    isa_ok($set10, 'Krang::DataSet');
    $set10->add(object => $_) for @stories;

    my $path10 = catfile(KrangRoot, 'tmp', '10stories.kds');
    $set10->write(path => $path10);
    ok(-e $path10 and -s $path10);
    END { unlink($path10) if $path10 and -e $path10 and not $DEBUG }

    # delete the floodfilled stories
    system("$undo > /dev/null 2>&1");

    # load the dataset with an import handler to collect imported objects
    my @imported;
    my $import10 = pkg('DataSet')->new(
        path            => $path10,
        import_callback => sub { push(@imported, $_[1]) }
    );
    isa_ok($import10, 'Krang::DataSet');
    $import10->import_all();

    # should be 10 stories
    is((grep { $_->isa('Krang::Story') } @imported), 10);

    # check category content
    my %story_cats  = map { ($_->url, $_) } map  { $_->categories } @stories;
    my %import_cats = map { ($_->url, $_) } grep { $_->isa('Krang::Category') } @imported;
    foreach my $import_cat (values %import_cats) {
        ok($story_cats{$import_cat->url});
        if ($story_cats{$import_cat->url}->parent) {
            is($story_cats{$import_cat->url}->parent->url, $import_cat->parent->url);
        }
    }

    # check story UUIDs
    my @loaded_uuids =
      map { $_->story_uuid } grep { $_->isa('Krang::Story') } @imported;
    is_deeply([sort @loaded_uuids], [sort @story_uuids]);

    # check story content
    my %imported = map { ($_->url, $_) }
      grep { $_->isa('Krang::Story') } @imported;
    foreach my $story (@stories) {
        my $import = $imported{$story->url};

        # there's a match
        ok($import);

        foreach_element {

            # check that element content is the same for all paragraphs
            if ($_->name eq 'paragraph') {
                is(($import->element->match($_->xpath))[0]->data(), $_->data);
            }

            if ($_->name eq 'issue_date') {
                is(($import->element->match($_->xpath))[0]->data()->mysql_datetime,
                    $_->data->mysql_datetime);
            }

            # BROKEN: this doesn't work because Krang::Media and
            # Krang::ElementClass may need to do a find() on categories to
            # load its URL.  Since the category object is already deleted
            # the call to url() fails.

            # check that story links point to stories with the right URLs
            #if ($_->class->isa('Krang::ElementClass::StoryLink')) {
            #    is(($import->element->match($_->xpath))[0]->data()->url,
            #       $_->data->url);
            #}

            # check that media links point to stories with the right URLs
            #if ($_->class->isa('Krang::ElementClass::MediaLink')) {
            #    is(($import->element->match($_->xpath))[0]->data()->url,
            #       $_->data->url);
            #}
        }

        #          $story->element;
    }

    # cleanup everything in the right order
    END {
        $_->delete for (grep { $_->isa('Krang::Media') } @imported);
        $_->delete for (grep { $_->isa('Krang::Story') } @imported);
        $_->delete
          for (
            sort { length($b->url) cmp length($a->url) }
            grep { defined $_->parent_id }
            grep { $_->isa('Krang::Category') } @imported
          );
        $_->delete for (grep { $_->isa('Krang::Site') } @imported);
        $_->delete for (grep { $_->isa('Krang::Contrib') } @imported);
    }

}

# try deleting a site a loading it from a data set
my $lsite = pkg('Site')->new(
    preview_url  => 'preview.lazarus.com',
    url          => 'lazarus.com',
    publish_path => '/tmp/lazarus',
    preview_path => '/tmp/lazarus'
);
$lsite->save();

$lset = pkg('DataSet')->new();
$lset->add(object => $lsite);

# it lives, yes?
my ($found) = pkg('Site')->find(url => 'lazarus.com', count => 1);
ok($found);

# this should fail
eval { $lset->import_all(no_update => 1) };
ok($@);

# it dies
$lsite->delete();
($found) = pkg('Site')->find(url => 'lazarus.com', count => 1);
ok(not $found);

# the resurection
$lset->import_all();
($found) = pkg('Site')->find(url => 'lazarus.com', count => 1);
ok($found);

END {
    (pkg('Site')->find(url => 'lazarus.com'))[0]->delete()
      if $STORY_DELETE;
}

# try the same with media
$filepath = catfile(KrangRoot, 't', 'media', 'krang.jpg');
$fh = new FileHandle $filepath;
my $lmedia = pkg('Media')->new(
    title         => 'test media object',
    category_id   => $category->category_id,
    media_type_id => 1,
    filename      => 'lazarus_lives.jpg',
    filehandle    => $fh
);
$lmedia->save();
$lset->add(object => $lmedia);

# it lives, yes?
($found) = pkg('Media')->find(url_like => '%lazarus_lives.jpg', count => 1);
ok($found);

# this should fail
eval { $lset->import_all(no_update => 1) };
ok($@);

# it dies
$lmedia->delete();
($found) = pkg('Media')->find(url_like => '%lazarus_lives.jpg', count => 1);
ok(not $found);

# the resurection
$lset->import_all();
($found) = pkg('Media')->find(url_like => '%lazarus_lives.jpg', count => 1);
ok($found);

END {
    (pkg('Media')->find(url_like => '%lazarus_lives.jpg'))[0]->delete()
      if $STORY_DELETE;
}

# try the same with template
my $ltemplate = pkg('Template')->new(
    filename    => 'abcd_fake.tmpl',
    category_id => $category->category_id,
    content     => 'this is the content here'
);

$ltemplate->save();
$ltemplate->mark_as_deployed();
$lset->add(object => $ltemplate);

# it lives, yes?
($found) = pkg('Template')->find(url => $ltemplate->url, count => 1);
ok($found);

# this should fail
eval { $lset->import_all(no_update => 1) };
ok($@);

# it dies
$ltemplate->delete();
($found) = pkg('Template')->find(url => $ltemplate->url, count => 1);
ok(not $found);

# the resurection
$lset->import_all();
($found) = pkg('Template')->find(url => $ltemplate->url, count => 1);
ok($found);

END {
    (pkg('Template')->find(url => $ltemplate->url))[0]->delete()
      if $STORY_DELETE;
}

# now test desks, groups, users, alerts
my $ldesk = pkg('Desk')->new(name => 'abc_test_desk');

my $lgroup = pkg('Group')->new(
    name                => 'abc_test_group',
    categories          => {$category->category_id => 'edit'},
    desks               => {$ldesk->desk_id => 'edit'},
    may_publish         => 1,
    may_checkin_all     => 1,
    admin_users         => 1,
    admin_users_limited => 1,
    admin_groups        => 1,
    admin_contribs      => 1,
    admin_sites         => 1,
    admin_categories    => 1,
    admin_jobs          => 1,
    admin_desks         => 1,
    asset_story         => 'edit',
    asset_media         => 'read-only',
    asset_template      => 'hide'
);

$lgroup->save;

my $luser = pkg('User')->new(
    email      => 'a@b.com',
    first_name => 'fname',
    last_name  => 'lname',
    group_ids  => ($lgroup->group_id),
    login      => 'abc_test_login',
    password   => 'passwd'
);

$luser->save;

$lset->add(object => $luser);

my $lalert = pkg('Alert')->new(
    user_id     => $luser->user_id,
    action      => 'move_to',
    category_id => $category->category_id,
    desk_id     => $ldesk->desk_id
);

$lalert->save;

$lset->add(object => $lalert);

# they live, yes?
($found) = pkg('User')->find(login => $luser->login, count => 1);
ok($found);
($found) = pkg('Group')->find(name => $lgroup->name, count => 1);
ok($found);
($found) = pkg('Desk')->find(name => $ldesk->name, count => 1);
ok($found);
($found) = pkg('Alert')->find(alert_id => $lalert->alert_id, count => 1);
ok($found);

# this should fail
eval { $lset->import_all(no_update => 1) };
ok($@);

# it dies
$luser->delete();
$lgroup->delete();
$ldesk->delete();
$lalert->delete();
($found) = pkg('User')->find(login => $luser->login, count => 1);
ok(not $found);
($found) = pkg('Group')->find(name => $lgroup->name, count => 1);
ok(not $found);
($found) = pkg('Desk')->find(name => $ldesk->name, count => 1);
ok(not $found);
($found) = pkg('Alert')->find(alert_id => $lalert->alert_id, count => 1);
ok(not $found);

# the resurection
$lset->import_all();
($found) = pkg('User')->find(login => $luser->login, count => 1);
my $uid = (pkg('User')->find(login => $luser->login))[0]->user_id;
ok($found);
($found) = pkg('Group')->find(name => $lgroup->name, count => 1);
ok($found);
($found) = pkg('Desk')->find(name => $ldesk->name, count => 1);
my $did = (pkg('Desk')->find(name => $ldesk->name))[0]->desk_id;
ok($found);

my $cid = (pkg('Category')->find(url => $category->url))[0]->category_id;
($found) =
  pkg('Alert')
  ->find(user_id => $uid, desk_id => $did, category_id => $cid, action => 'move_to', count => 1);
ok($found);

END {
    (pkg('Desk')->find(name => $ldesk->name))[0]->delete()
      if $STORY_DELETE;
}

END {
    (pkg('Group')->find(name => $lgroup->name))[0]->delete()
      if $STORY_DELETE;
}

END {
    (pkg('User')->find(login => $luser->login))[0]->delete()
      if $STORY_DELETE;
}

SKIP: {
    skip('Element tests only work for TestSet1', 1)
      unless (InstanceElementSet eq 'TestSet1');

    # create a story with an element tree and make sure it gets through an
    # export/import intact
    # create a new story
    my $big = pkg('Story')->new(
        categories => [$category],
        title      => "Big",
        slug       => "big",
        class      => "article"
    );
    $big->element->child('deck')->data("DECK DECK DECK");
    $big->save();

    my $bset = pkg('DataSet')->new();
    $bset->add(object => $big);

    ok(pkg('Story')->find(url => $big->url));
    $big->delete();
    ok(not pkg('Story')->find(url => $big->url));

    # first test to see if story URL conflict is caught
    my $cstory = pkg('Story')->new(
        categories => [$category2, $category],
        title      => "Big",
        slug       => "big",
        class      => "article"
    );

    $cstory->save;

    eval { $bset->import_all() };

    like($@, qr/A story object with a non-primary url/);

    $cstory->delete;

    $bset->import_all();
    ($big) = pkg('Story')->find(url => $big->url);
    ok($big);

    END {
        if (defined $big) { $big->delete() }
    }

    is($big->element->child('deck')->data, "DECK DECK DECK");

    # create a pair of stories that point to each other in a circle
    my $jack = pkg('Story')->new(
        categories => [pkg('Category')->find(category_id => $category->category_id)],
        title      => "Jack",
        slug       => "jack",
        class      => "cover"
    );
    $jack->save();

    # create a pair of stories that point to each other in a circle
    my $jill = pkg('Story')->new(
        categories => [pkg('Category')->find(category_id => $category2->category_id)],
        title      => "Jill",
        slug       => "jill",
        class      => "cover"
    );
    $jill->save();

    $jack->element->add_child(
        class => 'leadin',
        data  => $jill
    );
    $jill->element->add_child(
        class => 'leadin',
        data  => $jack
    );
    $jack->save();
    $jill->save();

    # serialize them
    my $j2set = pkg('DataSet')->new();
    $j2set->add(object => $jack);
    $j2set->add(object => $jill);
    isa_ok($j2set, 'Krang::DataSet');

    # should be just two stories
    is((grep { $_->[0]->isa('Krang::Story') } $j2set->list), 2);

    # write it out
    my $j2path = catfile(KrangRoot, 'tmp', 'j2.kds');
    $j2set->write(path => $j2path);
    ok(-e $j2path and -s $j2path);
    END { unlink($j2path) if $j2path and -e $j2path and not $DEBUG }

    $jack->delete();
    $jill->delete();

    # try an import
    $j2set->import_all;

    # should have them back
    my ($imported_jack) = pkg('Story')->find(url => $jack->url);
    isa_ok($imported_jack, 'Krang::Story');
    my ($imported_jill) = pkg('Story')->find(url => $jill->url);
    isa_ok($imported_jill, 'Krang::Story');

    # do they point to each other?
    is($imported_jack->element->child('leadin')->data->story_id, $imported_jill->story_id);
    is($imported_jill->element->child('leadin')->data->story_id, $imported_jack->story_id);

    END {
        $imported_jack->delete() if $imported_jack;
        $imported_jill->delete() if $imported_jill;
    }

    ####
    # test circular handling with respect to categories.
    my $c_cat = pkg('Category')->new(
        dir       => '/circtest',
        parent_id => $category->category_id
    );

    $c_cat->save();

    # create a media object
    my $c_media = pkg('Media')->new(
        title         => 'test media object',
        category_id   => $c_cat->category_id,
        media_type_id => 1
    );
    my $filepath = catfile(KrangRoot, 't', 'media', 'krang.jpg');
    my $fh = new FileHandle $filepath;
    $c_media->upload_file(filename => 'krang.jpg', filehandle => $fh);
    $c_media->save();

    # add an element to the category, linking to the media object.
    $c_cat->element->add_child(class => 'photo', data => $c_media);
    $c_cat->save();

    # serialize them
    my $circular_set = pkg('DataSet')->new();
    $circular_set->add(object => $c_cat);
    $circular_set->add(object => $c_media);

    # write it out
    my $circ_path = catfile(KrangRoot, 'tmp', 'circular_test.kds');
    $circular_set->write(path => $circ_path);
    ok(-e $circ_path and -s $circ_path);
    END { unlink($circ_path) if $circ_path and -e $circ_path and not $DEBUG }

    $c_media->delete();
    $c_cat->delete();

    # attempt an import.
    $circular_set->import_all();
    my ($imported_cat) = pkg('Category')->find(url => $c_cat->url);
    isa_ok($imported_cat, 'Krang::Category');
    my ($imported_med) = pkg('Media')->find(url => $c_media->url);
    isa_ok($imported_med, 'Krang::Media');

    # are the relationships correct?
    is($imported_cat->element->child('photo')->data->media_id,
        $imported_med->media_id, 'circular category check');
    is($imported_med->category_id, $imported_cat->category_id, 'circular category check');

    END {
        $imported_med->delete if $imported_med;
        $imported_cat->delete if $imported_cat;
    }

}

