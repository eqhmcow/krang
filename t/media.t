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

is ($media->thumbnail_path(), catfile((splitpath($media->{tempfile}))[1],"t__".$media->filename));


# create new contributor object to test associating with media
my $contrib = Krang::Contrib->new(prefix => 'Mr', first => 'Matthew', middle => 'Charles', last => 'Vella', email => 'mvella@thepirtgroup.com');
isa_ok($contrib, 'Krang::Contrib');
$contrib->contrib_type_ids(1,3);
$contrib->save();
END { $contrib->delete(); }

# add contributor to media
$media->contribs({ contrib_id      => $contrib->contrib_id, 
                   contrib_type_id => 3 });
is($media->contribs, 1);

# same object?
is(($media->contribs)[0]->contrib_id, $contrib->contrib_id);
is(($media->contribs)[0]->selected_contrib_type, 3);

# save it
$media->save();

# test file_path
like($media->file_path, qr/krang\.jpg$/);
like($media->file_path(relative => 1), qr/krang\.jpg$/);
is($media->file_path, catfile(KrangRoot, $media->file_path(relative => 1)));
ok(-f $media->file_path);

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

# delete it now
$m2->delete();

# delete other media object also
$medias[1]->delete();

