use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'History';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Media';
use Krang::ClassLoader Conf => qw (KrangRoot InstanceElementSet);
use File::Spec::Functions qw(catdir catfile splitpath);
use FileHandle;

BEGIN {
    my $found;
    foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        if (InstanceElementSet eq 'TestSet1') {
            last;
        }
    }
}

# set up site and category
my $site = pkg('Site')->new(
    preview_path => './sites/test1/preview/',
    preview_url  => 'preview.testsite1.com',
    publish_path => './sites/test1/',
    url          => 'testsite1.com'
);
$site->save();
isa_ok($site, 'Krang::Site');

END {
    $site->delete();
}

my ($category) = pkg('Category')->find(site_id => $site->site_id());

my $category_id = $category->category_id();

# create new media object
my $media =
  pkg('Media')->new(title => 'test media object', category_id => $category_id, media_type_id => 1);
isa_ok($media, 'Krang::Media');

END {
    $media->delete();
}

# upload media file
my $filepath = catfile(KrangRoot, 't', 'media', 'krang.jpg');
my $fh = new FileHandle $filepath;
$media->upload_file(filename => 'krang.jpg', filehandle => $fh);

# save it
$media->save();

my @events = pkg('History')->find(object => $media, order_by => 'action');

is($events[0]->object_id, $media->media_id, "object_id in history matches media_id");
is($events[0]->object_type, ref $media, "object_type stored properly in history");
is($events[0]->action, 'new', "history entry is new since media was created and saved");
is(
    $events[1]->action, 'save', "history entry is new since media was created and
saved"
);
is($events[1]->version, $media->version, "history version matches media version");

# perform a few other actions on the media then check that there are the
# appropriate nuber of events returned from Krang::History->find

$media->checkout();
$media->save();
$media->checkin();

@events = pkg('History')->find(object => $media);

is(@events, 4, "Four events found for media now");
