use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;
use Krang::Conf qw (KrangRoot);
use Krang::Contrib;
use Krang::Site;
use Krang::Category;
use File::Spec::Functions qw(catdir catfile splitpath);
use FileHandle;

BEGIN { use_ok('Krang::Media') }

# set up site and category
my $site = Krang::Site->new(preview_path => './sites/test1/preview/',
                            preview_url => 'preview.testsite1.com',
                            publish_path => './sites/test1/',
                            url => 'testsite1.com');
$site->save();
END { $site->delete(); }
isa_ok($site, 'Krang::Site');

my ($category) = Krang::Category->find(site_id => $site->site_id());

my $category_id = $category->category_id();

# create subcategory
my $subcat = Krang::Category->new( dir => 'subcat', parent_id => $category_id );
$subcat->save();
END { $subcat->delete() }
my $subcat_id = $subcat->category_id();

# create new media object
my $media = Krang::Media->new(title => 'test media object', category_id => $category_id);
isa_ok($media, 'Krang::Media');

# upload media file
my $filepath = catfile(KrangRoot,'t','media','krang.jpg');
my $fh = new FileHandle $filepath;
$media->upload_file(filename => 'krang.jpg', filehandle => $fh);

is ($media->thumbnail_path(),
    catfile((splitpath($media->{tempfile}))[1], "t__".$media->filename),
    "Thumbnail path looks right" );


# check url and preview_url
is($media->url, 'testsite1.com/krang.jpg', "URL looks right");
is($media->preview_url, 'preview.testsite1.com/krang.jpg', "Preview URL looks right");

# create new contributor object to test associating with media
my $contrib = Krang::Contrib->new(prefix => 'Mr', first => 'Matthew', middle => 'Charles', last => 'Vella', email => 'mvella@thepirtgroup.com');
isa_ok($contrib, 'Krang::Contrib');
$contrib->contrib_type_ids(1,3);
$contrib->save();
END { $contrib->delete(); }

# add contributor to media
$media->contribs({ contrib_id      => $contrib->contrib_id, 
                   contrib_type_id => 3 });
is($media->contribs, 1, "add contributor to media");

# same object?
is(($media->contribs)[0]->contrib_id, $contrib->contrib_id, "Contrib set");
is(($media->contribs)[0]->selected_contrib_type, 3, "Contrib selected type set");

# save it
$media->save();

# test file_path
like($media->file_path, qr/krang\.jpg$/, "Absolute path looks right after save");
like($media->file_path(relative => 1), qr/krang\.jpg$/, "Relative path looks right after save");
is($media->file_path, catfile(KrangRoot, $media->file_path(relative => 1)), "Filepath looks right");
ok(-f $media->file_path, "Media file is found on hard disk");

# save again
$media->save();

# test file_path
like($media->file_path, qr/krang\.jpg$/, "Path looks right after second save");
like($media->file_path(relative => 1), qr/krang\.jpg$/, "Relative path looks right after second save");
is($media->file_path, catfile(KrangRoot, $media->file_path(relative => 1)), "Filepath still looks right");
ok(-f $media->file_path, "Media file is still found on hard disk");

# try to load it again and see if the file is still available
my ($copy) = Krang::Media->find(media_id => $media->media_id);
is($media->file_path, $copy->file_path);
ok(-f $copy->file_path);

$fh = new FileHandle $filepath;

# create another media object
my $media2 = Krang::Media->new(title => 'test media object 2', category_id => $subcat_id, filename => 'krang.jpg', filehandle => $fh);
isa_ok($media2, 'Krang::Media');

# add 2 contributors to media
$media2->contribs($media->contribs,
                  { contrib_id      => $contrib->contrib_id, 
                    contrib_type_id => 1 });
is($media2->contribs, 2);
is(($media2->contribs)[0]->contrib_id, $contrib->contrib_id);
is(($media2->contribs)[0]->selected_contrib_type, 3);
is(($media2->contribs)[1]->contrib_id, $contrib->contrib_id);
is(($media2->contribs)[1]->selected_contrib_type, 1);

# save second media file
$media2->save();
like($media->file_path, qr/krang\.jpg$/);
ok(-f $media->file_path);

# find the media objects we just created, sorting in reverse order 
# that they were created (media_id desc)
my @medias = Krang::Media->find(filename => 'krang.jpg', order_by => 'media_id', order_desc => 1);

# make sure 2 are returned
is(scalar @medias, 2);

# assign what should be the second created (first returned) to var
my $m2 = $medias[0];

# check title
is ($m2->title(), 'test media object 2');

# check contribs
is($m2->contribs, 2);
is(($m2->contribs)[0]->contrib_id, $contrib->contrib_id);
is(($m2->contribs)[0]->selected_contrib_type, 3);
is(($m2->contribs)[1]->contrib_id, $contrib->contrib_id);
is(($m2->contribs)[1]->selected_contrib_type, 1);

# remove contribs
$m2->clear_contribs();
is($m2->contribs, 0);

# check title of other media object too
is ($medias[1]->title(), 'test media object');

# check filename 
is ($m2->filename(), 'krang.jpg');

# check file size
is ($m2->file_size(), 2021);

# check MIME type
is ($m2->mime_type(), 'image/jpeg');

# mark as checked out
$m2->checkout();

# change the title
$m2->title('new title');

is ($m2->thumbnail_path(), catfile(KrangRoot,'data','media',Krang::Conf->instance,$m2->_media_id_path,$m2->version,"t__".$m2->filename));

# upload another media file
$filepath = catfile(KrangRoot,'t','media','krang.gif');
$fh = new FileHandle $filepath;
$m2->upload_file(filename => 'krang.gif', filehandle => $fh);

# did that register?
like($m2->file_path, qr/krang\.gif$/);
ok(-f $m2->file_path);

# save again
$m2->save();
like($m2->file_path, qr/krang\.gif$/);
ok(-f $m2->file_path);

# test loading of old version with find()
my $old_version = Krang::Media->find( media_id => $m2->media_id, version => 1);

is($old_version->title(), 'test media object 2');
is($old_version->version(), '1');

# revert back to version 1
$m2->revert(1);

# check title to see if reverted
is ($m2->title(), 'test media object 2');

# check filename to see if reverted
is ($m2->filename(), 'krang.jpg');
like ($m2->file_path(), qr/krang\.jpg$/);

# and save
$m2->save();

# check version number
is ($m2->version(), 3);

# checkin
$m2->checkin();


# test mark_as_published
$m2->mark_as_published();

isnt($m2->publish_date, undef, 'Krang::Media->mark_as_published()');
is($m2->published_version, $m2->version(), 'Krang::Media->mark_as_published()');
is($m2->checked_out(), 0, 'Krang::Media->mark_as_published()');



# test simple_search by id
my @temp_media = Krang::Media->find( simple_search => $m2->media_id);

is($temp_media[0]->media_id, $m2->media_id);
is($temp_media[0]->title, $m2->title);

# test simple_search by word in title 
# COMMENTED OUT FOR NOW b/c this could fail with preexisting media
#@temp_media = Krang::Media->find( simple_search => 'test media object' );

#is($temp_media[0]->media_id, $media->media_id);
#is($temp_media[0]->title, $media->title);

# delete it now
Krang::Media->delete($m2->media_id);

# delete other media object also
$medias[1]->delete();


### Permission tests #################
#
{
    my $unique = time();

    # create a new site for testing
    my $ptest_site = Krang::Site->new( url => "$unique.com",
                                       preview_url => "preview.$unique.com",
                                       preview_path => 'preview/path/',
                                       publish_path => 'publish/path/' );
    $ptest_site->save();
    my $ptest_site_id = $ptest_site->site_id();
    my ($ptest_root_cat) = Krang::Category->find(site_id=>$ptest_site_id);

    my $media = Krang::Media->new(
                                  title => 'Root Cat media', 
                                  category_id => $ptest_root_cat->category_id(), 
                                  filename => 'krang.jpg', 
                                  filehandle => $fh
                                 );
    $media->save();
    my @medias = ($media);

    # Create some descendant categories and media
    my @ptest_cat_dirs = qw(A1 A2 B1 B2);
    my @ptest_categories = ();
    for (@ptest_cat_dirs) {
        my $parent_id = ( /1/ ) ? $ptest_root_cat->category_id() : $ptest_categories[-1]->category_id() ;
        my $newcat = Krang::Category->new( dir => $_,
                                           parent_id => $parent_id );
        $newcat->save();
        push(@ptest_categories, $newcat);

        # Add media in this category
        my $media = Krang::Media->new(
                                      title => $_ .' media', 
                                      category_id => $newcat->category_id(), 
                                      filename => 'krang.jpg', 
                                      filehandle => $fh
                                     );
        $media->save();
        push(@medias, $media);
    }


    # Verify that we have permissions
    my ($tmp) = Krang::Media->find(media_id=>$medias[-1]->media_id);
    is($tmp->may_see, 1, "Found may_see");
    is($tmp->may_edit, 1, "Found may_edit");

    # Change group asset_media permissions to "read-only" and check permissions
    my ($admin_group) = Krang::Group->find(group_id=>1);
    $admin_group->asset_media("read-only");
    $admin_group->save();

    ($tmp) = Krang::Media->find(media_id=>$medias[-1]->media_id);
    is($tmp->may_see, 1, "asset_media read-only may_see => 1");
    is($tmp->may_edit, 0, "asset_media read-only may_edit => 0");

    # Change group asset_media permissions to "hide" and check permissions
    $admin_group->asset_media("hide");
    $admin_group->save();

    ($tmp) = Krang::Media->find(media_id=>$medias[-1]->media_id);
    is($tmp->may_see, 1, "asset_media hide may_see => 1");
    is($tmp->may_edit, 0, "asset_media hide may_edit => 0");

    # Reset asset_media to "edit"
    $admin_group->asset_media("edit");
    $admin_group->save();

    # Change permissions to "read-only" for one of the branches by editing the Admin group
    my $ptest_cat_id = $ptest_categories[0]->category_id();
    $admin_group->categories($ptest_cat_id => "read-only");
    $admin_group->save();

    # Try to save media to read-only catgory
    $tmp = Krang::Media->new( title => "No media", 
                              category_id => $ptest_cat_id, 
                              filename => 'krang.jpg', 
                              filehandle => $fh );
    eval { $tmp->save() };
    isa_ok($@, "Krang::Media::NoCategoryEditAccess", "save() to read-only category throws exception");

    # Check permissions for that category
    ($tmp) = Krang::Media->find(media_id=>$medias[1]->media_id);
    is($tmp->may_see, 1, "read-only may_see => 1");
    is($tmp->may_edit, 0, "read-only may_edit => 0");

    # Check permissions for descendant of that category
    my $ptest_media_id = $medias[2]->media_id();
    ($tmp) = Krang::Media->find(media_id=>$ptest_media_id);
    is($tmp->may_see, 1, "descendant read-only may_see => 1");
    is($tmp->may_edit, 0, "descendant read-only may_edit => 0");

    # Check permissions for sibling
    $ptest_media_id = $medias[3]->media_id();
    ($tmp) = Krang::Media->find(media_id=>$ptest_media_id);
    is($tmp->may_see, 1, "sibling edit may_see => 1");
    is($tmp->may_edit, 1, "sibling edit may_edit => 1");

    # Try to save "read-only" media -- should die
    $ptest_media_id = $medias[2]->media_id();
    ($tmp) = Krang::Media->find(media_id=>$ptest_media_id);
    eval { $tmp->save() };
    isa_ok($@, "Krang::Media::NoEditAccess", "save() on read-only media exception");

    # Try to delete()
    eval { $tmp->delete() };
    isa_ok($@, "Krang::Media::NoEditAccess", "delete() on read-only media exception");

    # Try to checkout()
    eval { $tmp->checkout() };
    isa_ok($@, "Krang::Media::NoEditAccess", "checkout() on read-only media exception");

    # Try to checkin()
    eval { $tmp->checkin() };
    isa_ok($@, "Krang::Media::NoEditAccess", "checkin() on read-only media exception");

    # Change other branch to "hide"
    $ptest_cat_id = $ptest_categories[2]->category_id();
    $admin_group->categories($ptest_cat_id => "hide");
    $admin_group->save();

    # Check permissions for that category
    $ptest_media_id = $medias[3]->media_id();
    ($tmp) = Krang::Media->find(media_id=>$ptest_media_id);
    is($tmp->may_see, 0, "hide may_see => 0");
    is($tmp->may_edit, 0, "hide may_edit => 0");

    # Get count of all media below root category -- should return all (5)
    my $ptest_count = Krang::Media->find(count=>1, below_category_id=>$ptest_root_cat->category_id());
    is($ptest_count, 5, "Found all media by default");

    # Get count with "may_see=>1" -- should return root + one branch (3)
    $ptest_count = Krang::Media->find(may_see=>1, count=>1, below_category_id=>$ptest_root_cat->category_id());
    is($ptest_count, 3, "Hide hidden media");

    # Get count with "may_edit=>1" -- should return just root
    $ptest_count = Krang::Media->find(may_edit=>1, count=>1, below_category_id=>$ptest_root_cat->category_id());
    is($ptest_count, 1, "Hide un-editable media");

    # Delete temp media
    for (reverse@medias) {
        $_->delete();
    }

    # Delete temp categories
    for (reverse@ptest_categories) {
        $_->delete();
    }

    # Delete site
    $ptest_site->delete();
}

