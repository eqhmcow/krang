use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::Script;
use Krang::History;
use Krang::Category;
use Krang::Site;
use Krang::Media;
use Krang::Conf qw (KrangRoot);
use File::Spec::Functions qw(catdir catfile splitpath);
use FileHandle;

# set up site and category
my $site = Krang::Site->new(preview_path => './sites/test1/preview/',
                            preview_url => 'preview.testsite1.com',
                            publish_path => './sites/test1/',
                            url => 'testsite1.com');
$site->save();
isa_ok($site, 'Krang::Site');

END {
    $site->delete();
}

my ($category) = Krang::Category->find(site_id => $site->site_id());

my $category_id = $category->category_id();

# create new media object
my $media = Krang::Media->new(title => 'test media object', category_id => $category_id);
isa_ok($media, 'Krang::Media');

END {
    $media->delete();
}

# upload media file
my $filepath = catfile(KrangRoot,'t','media','krang.jpg');
my $fh = new FileHandle $filepath;
$media->upload_file(filename => 'krang.jpg', filehandle => $fh);

# save it
$media->save();

my @events = Krang::History->find( object => $media );

is($events[0]->object_id, $media->media_id, "object_id in history matches media_id");
is($events[0]->object_type, ref $media, "object_type stored properly in history");
is($events[0]->action, 'save', "history entry is a save since media was saved");
is($events[0]->version, $media->version, "history version matches media version");

# perform a few other actions on the media then check that there are the 
# appropriate nuber of events returned from Krang::History->find

$media->checkout();
$media->save();
$media->checkin();

@events = Krang::History->find( object => $media );

is(@events, 4, "Four events found for media now");
