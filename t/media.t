use Test::More qw(no_plan);
use strict;
use warnings;
use Krang;
use Krang::Conf qw (KrangRoot);
use Krang::Contrib;
use File::Spec::Functions qw(catdir catfile);
use FileHandle;

BEGIN { use_ok('Krang::Media') }

# create new media object
my $media = Krang::Media->new(title => 'test media object', category_id => 1);
isa_ok($media, 'Krang::Media');

# upload media file
my $filepath = catfile(KrangRoot,'t','media','krang.jpg');
my $fh = new FileHandle $filepath;
$media->upload_file(filename => 'krang.jpg', filehandle => $fh);


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

$fh = new FileHandle $filepath;

# create another media object
my $media2 = Krang::Media->new(title => 'test media object 2', category_id => 1, filename => 'krang.jpg', filehandle => $fh);
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

# find the media objects we just created, sorting in reverse order 
# that they were created (media_id desc)
my @medias = Krang::Media->find(filename => 'krang.jpg', order_by => 'media_id', order_desc => 1, category_id => 1);

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

# begin edit
$m2->prepare_for_edit();

# change the title
$m2->title('new title');

is ($m2->thumbnail_path(), catfile(KrangRoot,'data','media',$m2->_media_id_path,$m2->version,"t__".$m2->filename));

# upload another media file
$filepath = catfile(KrangRoot,'t','media','krang.gif');
$fh = new FileHandle $filepath;
$m2->upload_file(filename => 'krang.gif', filehandle => $fh);

# save again
$m2->save();

# continue with edit
$m2->prepare_for_edit();

# revert back to version 1
$m2->revert(1);

# check title to see if reverted
is ($m2->title(), 'test media object 2');

# check filename to see if reverted
is ($m2->filename(), 'krang.jpg');

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

