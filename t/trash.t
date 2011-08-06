use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader Conf => qw(InstanceElementSet KrangRoot);
use Krang::ClassLoader DB   => qw(dbh);
use Krang::ClassLoader 'Test::Content';

use File::Spec::Functions qw(catfile);
use FileHandle;

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

# allow 12 items in trash
BEGIN {
    my $trash = qq{TrashMaxItems "12"\n};
    my $fh    = IO::Scalar->new(\$trash);
    $Krang::Conf::CONF->read($fh);
}

# trash object attribs
my @trash_object_attribs = qw(id type title class url date version may_see may_edit linkto);

BEGIN { use_ok(pkg('Trash')) }

my $dbh = dbh();

# use pkg('Test::Content') to create sites.
my $creator = pkg('Test::Content')->new;

END {
    $creator->cleanup();
}

my $site = $creator->create_site(
    preview_url  => 'trash_test.preview.com',
    publish_url  => 'trash_test.com',
    preview_path => '/tmp/trash_and_retire_test_preview',
    publish_path => '/tmp/trash_and_retire_test_publish'
);

isa_ok($site, 'Krang::Site');

# create categories.
my $category = $creator->create_category();
isa_ok($category, 'Krang::Category');

# setup group with asset permissions
my $group = pkg('Group')->new(
    name           => 'Has no restore permissions',
    asset_story    => 'read-only',
    asset_media    => 'read-only',
    asset_template => 'read-only',
);
$group->save();
END { $group->delete }

# put a user into this group
my $user = pkg('User')->new(
    login     => 'bob',
    password  => 'bobspass',
    group_ids => [$group->group_id],
);
$user->save();
END { $user->delete }

test_story_trashing();
test_media_trashing();

#    --- End Main ---

sub test_story_trashing {
  SKIP: {
        skip('Story tests only work for TestSet1', 1)
          unless (InstanceElementSet eq 'TestSet1');

        # create 12 stories
        my @stories;
        push @stories, $creator->create_story() for 1 .. 12;

        # move them to the trashbin (may hold TrashMaxItems, set to 12)
        $_->trash, sleep 1 for @stories;

        # test trash find with stories
        my @trash = pkg('Trash')->find();

        ok(not grep { not defined $_ } @trash);

        # trash objects have required attribs
        is(defined($trash[0]{$_}), 1, "Story trash object attrib '$_' is defined")
          for @trash_object_attribs;

        foreach my $story (@stories) {
            ok(grep { $story->story_id == $_->{id} } @trash);
        }

        # verify that they have entries in the trash table
        for my $story (@stories) {
            my $story_id = $story->story_id;
            my $found    = $dbh->selectall_arrayref(<<SQL);
SELECT * FROM trash
WHERE  object_type = 'story'
AND    object_id   = $story_id
SQL
            is(@$found, 1, "Found Story $story_id in trash");
        }

        # create one more store and trash it
        my $story = $creator->create_story();
        push(@stories, $story);
        $story->trash();

        # Story 0 should be gone
        my $sid0  = $stories[0]->story_id;
        my $found = $dbh->selectall_arrayref(<<SQL);
SELECT * FROM trash
WHERE  object_type = 'story'
AND    object_id   = $sid0
SQL
        is(@$found, 0, "Story $sid0 has been pruned (gone from the trash table.");

        $found = $dbh->selectall_arrayref(<<SQL);
SELECT * from story
WHERE  story_id = $sid0
SQL
        is(@$found, 0, "Story $sid0 has been pruned (gone from the story table.");

        # Story 12 should be there
        my $sid12 = $stories[12]->story_id;
        $found = $dbh->selectall_arrayref(<<SQL);
SELECT * FROM trash
WHERE  object_type = 'story'
AND    object_id   = $sid12
SQL
        is(@$found, 1, "Found Story $sid12 in Trash.");

        # restore them to live
        pkg('Trash')->restore(object => $_) for @stories;

        # stories' trashed flag should be 0
        is($_->trashed, 0, "Story " . $_->story_id . " trashed flag is zero after restore")
          for @stories;

        ### test exceptions on restore
        #
        note("");
        note("1. Test restoring slug-provided story when its URL is occupied by another story");
        note("");
        $story = $stories[3];
        my $sid = $story->story_id;
        $story->trash;

        # should be trashed
        is($story->trashed, 1, "Story $sid lives in trash");

        # create another story of type 'article' with the same URL
        my $dupe = pkg('Story')->new(
            categories => [$story->categories],
            title      => $story->title,
            slug       => $story->slug,
            class      => $story->class->name
        );
        $dupe->save;

        note("Created another story having a slug with the same URL as Story $sid");

        # try to restore our story
        note("Try to restore Story $sid - should throw Krang::Story::DuplicateURL exception");
        eval { pkg('Trash')->restore(object => $story) };
        isa_ok($@, 'Krang::Story::DuplicateURL');
        is(ref($@->stories), 'ARRAY',
            "Stories array of Krang::Story::DuplicateURL exception is set");
        is($dupe->url, ${$@->stories}[0]{url}, "Our dupe found in exception's story list");
        _verify_flag_status($story, 1);

        # delete dupe and try again
        $dupe->delete;
        eval { pkg('Trash')->restore(object => $story) };
        ok(!$@) and note("After deleting dupe, restoring Story $sid was successful");
        _verify_flag_status($story);

        note("");
        note("2. Test story restoring when story's URL is occupied by a category");
        note("");
        $story->trash;

        # should be trashed again
        is($story->trashed, 1, "Story $sid lives in trash again");

        # create category having the story's URL
        my $dupe_cat = pkg('Category')->new(
            site_id   => $site->site_id,
            parent_id => $story->category->category_id,
            dir       => $story->slug
        );
        $dupe_cat->save;
        my $cid = $dupe_cat->category_id;

        is($dupe_cat->url, $story->url, "Created category $cid with same URL as Story $sid");

        note("Try to restore the story - should throw a Krang::Story::DuplicateURL exception");
        eval { pkg('Trash')->restore(object => $story) };
        isa_ok($@, 'Krang::Story::DuplicateURL');
        is(ref($@->categories), 'ARRAY',
            "Categories array of Krang::Story::DuplicateURL exception is set");
        is(
            $dupe_cat->url,
            ${$@->categories}[0]{url},
            "Our category $cid found in exception's category list"
        );
        _verify_flag_status($story, 1);

        # delete dupe and try again
        $dupe_cat->delete;
        eval { pkg('Trash')->restore(object => $story) };
        ok(!$@) and note("After deleting dupe category $cid, restoring Story $sid was successful");
        _verify_flag_status($story);

        note("");
        note("3. Test restoring slugless story when its URL is occupied by another story");
        note("");

        # create a slugless story
        $story = $creator->create_story(slug => '');
        unshift @stories, $story;
        $sid = $story->story_id;
        $story->trash;

        # should be trashed
        is($story->trashed, 1, "Story $sid lives in trash");

        # create another slugless story with the same URL
        $dupe = pkg('Story')->new(
            categories => [$story->categories],
            title      => $story->title,
            slug       => $story->slug,
            class      => $story->class->name
        );
        $dupe->save;
        my $did = $dupe->story_id;

        note("Created another slugless story $did with the same URL as Story $sid");

        # try to restore our story
        note("Try to restore Story $sid - should throw Krang::Story::DuplicateURL exception");
        eval { pkg('Trash')->restore(object => $story) };
        isa_ok($@, 'Krang::Story::DuplicateURL');
        is(ref($@->stories), 'ARRAY',
            "Stories array of Krang::Story::DuplicateURL exception is set");
        is(
            $dupe->url,
            ${$@->stories}[0]{url},
            "Our dupe Story $did found in exception's story list"
        );
        _verify_flag_status($story, 1);

        # delete dupe and try again
        $dupe->delete;
        eval { pkg('Trash')->restore(object => $story) };
        ok(!$@) and note("After deleting dupe story $did, restoring Story $sid was successful");
        _verify_flag_status($story);

        note("");
        note("4. Test restoring Story without restore permission");
        note("");
        $story->trash;

        # should be trashed
        is($story->trashed, 1, "Story $sid lives in trash");

        {
            note("We are now a user without restore permissions");
            local $ENV{REMOTE_USER} = $user->user_id;

            note(
                "Trying to restore Story $sid - should throw a Krang::Story::NoRestoreAccess exception"
            );

            # fetch it again, so that may_edit flag is correctly set on $story object
            my ($story) = pkg('Story')->find(story_id => $sid);

            eval { pkg('Trash')->restore(object => $story) };

            isa_ok($@, 'Krang::Story::NoRestoreAccess');
            _verify_flag_status($story, 1);
        }

        pkg('Trash')->restore(object => $_) for @stories;
    }
}

sub test_media_trashing {

    # create 12 media
    my @media;

    # first media (will be pruned from trashbin)
    my $media0 = pkg('Media')->new(
        category_id   => $category->category_id,
        title         => 'some title',
        media_type_id => 1,
    );
    isa_ok($media0, 'Krang::Media');
    my $mfp = catfile(KrangRoot, 't', 'media', 'krang.jpg');
    my $mfh = new FileHandle $mfp;
    $media0->upload_file(filename => 'krang.jpg', filehandle => $mfh);
    $media0->save;
    isa_ok($media0, 'Krang::Media');

    push @media, $creator->create_media(format => 'png') for 1 .. 11;

    # move them all to the trashbin (may hold TrashMaxItems, set to 12)
    $media0->trash;
    sleep 1;
    $_->trash, sleep 1 for @media;

    # test trash find with media
    my @trash = pkg('Trash')->find();

    ok(not grep { not defined $_ } @trash);

    is(defined($trash[0]{$_}), 1, "Media trash object attrib '$_' is defined")
      for @trash_object_attribs;

    foreach my $media (@media) {
        ok(grep { $media->media_id == $_->{id} } @trash);
    }

    # verify that they have entries in the trash table
    for my $media (@media) {
        my $media_id = $media->media_id;
        my $found    = $dbh->selectall_arrayref(<<SQL);
SELECT * FROM trash
WHERE  object_type = 'media'
AND    object_id   = $media_id
SQL
        is(@$found, 1, "Found Media $media_id in trash");
    }

    # create one more store and trash it
    my $media = $creator->create_media();
    push(@media, $media);
    $media->trash();

    # Media 0 should be gone
    my $media0_id = $media0->media_id;
    my $found     = $dbh->selectall_arrayref(<<SQL);
SELECT * FROM trash
WHERE  object_type = 'media'
AND    object_id   = $media0_id
SQL
    is(@$found, 0, "Media $media0_id has been pruned (gone from trash table).");

    $found = $dbh->selectall_arrayref(<<SQL);
SELECT * FROM media
WHERE  media_id = $media0_id
SQL

    is(@$found, 0, "Media $media0_id has been pruned (gone from media table).");

    # Media 11 should be there
    my $media11 = $media[11]->media_id;
    $found = $dbh->selectall_arrayref(<<SQL);
SELECT * FROM trash
WHERE  object_type = 'media'
AND    object_id   = $media11
SQL
    is(@$found, 1, "Found Media $media11 in Trash.");

    # restore them to live
    pkg('Trash')->restore(object => $_) for @media;

    # media's trashed flag should be 0
    is($_->trashed, 0, "Media's trashed flag is zero after restore") for @media;

    ### test exceptions on restore
    #
    note("");
    note("1. Test restoring media when its URL is occupied by another media");
    note("");
    $media = $media[3];
    my $mid = $media->media_id;
    $media->trash;

    # should be trashed
    is($media->trashed, 1, "Media $mid lives in trash");

    # create another media of type 'article' with the same URL
    (my $filename = $media->filename) =~ s/\.png$//;

    my $dupe = pkg('Media')->new(
        category_id   => $media->category_id,
        title         => $media->title,
        media_type_id => $media->media_type_id,
    );
    isa_ok($dupe, 'Krang::Media');
    my $fn = $media->file_path;
    my $fh = new FileHandle $fn;
    $dupe->upload_file(filename => $media->filename, filehandle => $fh);
    $dupe->save;

    note("Created another media having the same URL as Media $mid");

    # try to restore our media
    note("Try to restore Media $mid - should throw Krang::Media::DuplicateURL exception");
    eval { pkg('Trash')->restore(object => $media) };
    isa_ok($@, 'Krang::Media::DuplicateURL');
    is($dupe->media_id, $@->media_id, "Our dupe found in exception's media_id attrib");
    _verify_flag_status($media, 1);

    # delete dupe and try again
    $dupe->delete;
    eval { pkg('Trash')->restore(object => $media) };
    ok(!$@) and note("After deleting dupe, restoring Media $mid was successful");
    _verify_flag_status($media);

    note("");
    note("2. Test restoring Media without restore permission");
    note("");
    $media->trash;

    # should be trashed
    is($media->trashed, 1, "Media $mid lives in trash");

    {
        note("We are now a user without restore permissions");
        local $ENV{REMOTE_USER} = $user->user_id;

        note("Trying to restore Media $mid - should throw a Krang::Media::NoRestoreAccess exception");

        # fetch it again, so that may_edit flag is correctly set on $media object
        my ($media) = pkg('Media')->find(media_id => $mid);

        eval { pkg('Trash')->restore(object => $media) };

        isa_ok($@, 'Krang::Media::NoRestoreAccess');
        _verify_flag_status($media, 1);
    }

    pkg('Trash')->restore(object => $_) for @media;
}

sub _verify_flag_status {
    my ($object, $trashed) = @_;
    my $id_meth = $object->id_meth;
    my $oid     = $object->$id_meth;
    my $Object  = ucfirst($object->moniker);
    is($object->checked_out, 0, "$Object $oid flag checked_out    0") unless $Object eq 'Media';
    isnt($object->checked_out_by, 1, "$Object $oid flag checked_out_by 0");
    is(
        $object->trashed,
        ($trashed ? 1 : 0),
        "$Object $oid flag trashed        " . ($trashed ? 1 : 0)
    );
}
