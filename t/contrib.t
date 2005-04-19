use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Media';
use Krang::ClassLoader 'Site';
use Imager;
use File::Spec::Functions;
use File::Path;
use Krang::ClassLoader Conf => qw(KrangRoot instance InstanceElementSet);



BEGIN { use_ok(pkg('Contrib')) }

# Site params
my $preview_url = 'publishtest.preview.com';
my $publish_url = 'publishtest.com';
my $preview_path = '/tmp/krangpubtest_preview';
my $publish_path = '/tmp/krangpubtest_publish';

# create a site and category for dummy story
my $site = pkg('Site')->new(preview_url  => $preview_url,
                            url          => $publish_url,
                            preview_path => $preview_path,
                            publish_path => $publish_path
                           );
$site->save();

END {
    $site->delete();
    rmtree $preview_path;
    rmtree $publish_path;
}


my ($category) = pkg('Category')->find(site_id => $site->site_id());
$category->save();



# create new contributor object
my $contrib = pkg('Contrib')->new(prefix => 'Mr', first => 'Matthew', middle => 'Charles', last => 'Vella', email => 'mvella@thepirtgroup.com');
isa_ok($contrib, 'Krang::Contrib');

# test full_name
is($contrib->full_name, "Mr Matthew Charles Vella");
$contrib->suffix("The Dude");
is($contrib->full_name, "Mr Matthew Charles Vella, The Dude");
$contrib->suffix("");
is($contrib->full_name, "Mr Matthew Charles Vella");

$contrib->contrib_type_ids(1,3);
$contrib->selected_contrib_type(1);

my @contrib_type_ids = $contrib->contrib_type_ids();
is("@contrib_type_ids", "1 3");
is($contrib->selected_contrib_type, 1);

$contrib->save();

my $contrib_id = $contrib->contrib_id();

my @contrib_object = pkg('Contrib')->find( contrib_id => $contrib_id );

my $contrib2 = $contrib_object[0];

is($contrib2->first, 'Matthew');
is($contrib2->contrib_type_ids()->[0], 1);
is($contrib2->contrib_type_ids()->[1], 3);

$contrib2->contrib_type_ids(2,4);

$contrib2->save();

my @contrib_object2 = pkg('Contrib')->find( full_name => 'matt vella' );

my $contrib3 = $contrib_object2[0];

is($contrib3->contrib_id, $contrib_id);

# test count
my $count = pkg('Contrib')->find( full_name => 'matt vella',
                                  count     => 1 );
is($count, 1);


# Test ability to make a change to an existing record and save()
$contrib2->first('George1234');
$contrib2->save();

# Has contrib2 been updated in database?
my ($contrib2loaded) = pkg('Contrib')->find( contrib_id => $contrib2->contrib_id() );
is($contrib2loaded->first(), 'George1234');


## Test simple_search()
#
# Should find one
my @ss_contribs = pkg('Contrib')->find(simple_search=>'George1234 Vella');
is(scalar(@ss_contribs), 1);

# Should find one
@ss_contribs = pkg('Contrib')->find(simple_search=>'George1234');
is(scalar(@ss_contribs), 1);

# Should find one
@ss_contribs = pkg('Contrib')->find(simple_search=>'Vella');
is(scalar(@ss_contribs), 1);

# Should find NONE
@ss_contribs = pkg('Contrib')->find(simple_search=>'George1234 Carlin');
is(scalar(@ss_contribs), 0);

# Clean up added contrib
$contrib2->delete();

# create a few contribs to test ordering
my @contribs;
push(@contribs,
     pkg('Contrib')->new(first => 'Bohemia', last => 'Bolger'),
     pkg('Contrib')->new(first => 'Alvin', last => 'Arthur'),
     pkg('Contrib')->new(first => 'Conifer', last => 'Caligula'));
$_->contrib_type_ids(1) for @contribs;
$_->save for @contribs;
END { $_->delete for @contribs };
my %ids = map { $_->contrib_id, 1 } @contribs;

my @results = grep { $ids{$_->contrib_id} } 
  pkg('Contrib')->find(order_by => 'first');
is(@results, 3);
is($results[0]->contrib_id, $contribs[1]->contrib_id);
is($results[1]->contrib_id, $contribs[0]->contrib_id);
is($results[2]->contrib_id, $contribs[2]->contrib_id);

@results = grep { $ids{$_->contrib_id} } 
  pkg('Contrib')->find(order_by => 'first', order_desc => 1);
is(@results, 3);
is($results[2]->contrib_id, $contribs[1]->contrib_id);
is($results[1]->contrib_id, $contribs[0]->contrib_id);
is($results[0]->contrib_id, $contribs[2]->contrib_id);

@results = grep { $ids{$_->contrib_id} } 
  pkg('Contrib')->find(order_by => 'last,first', order_desc => 1);
is(@results, 3);
is($results[2]->contrib_id, $contribs[1]->contrib_id);
is($results[1]->contrib_id, $contribs[0]->contrib_id);
is($results[0]->contrib_id, $contribs[2]->contrib_id);


# Test exclude_contrib_ids: Filter set of contribs based on ID
{
    # Create set of contribs
    my @first_names = qw(Jesse Matt Sam Rudy Adam Peter);
    my @last_names = qw(One Two Three Four Five Six);
    my @types = qw(1 2 3);
    my @new_contribs = ();
    for (0..5) {
        my $c = pkg('Contrib')->new(
                            first => $first_names[$_],
                            last => "TestGuy_" . $last_names[$_],
                            contrib_type_ids => [ $types[rand(3)] ],
                           );
        $c->save();
        push(@new_contribs, $c);
    }

    my @exclude_contrib_ids = map { $_->contrib_id() } @new_contribs[0..2];

    # Select back contribs, with and without exclusions.  We should get exactly three more without
    my $count = pkg('Contrib')->find(count=>1);
    my $count_excluded = pkg('Contrib')->find(count=>1, exclude_contrib_ids=>\@exclude_contrib_ids);

    # Is that what we got?
    is(($count - $count_excluded), 3, "exclude_contrib_ids");

    # Delete test contribs
    $_->delete() for (@new_contribs);
}


# make sure contribs without middle names are caught as dups
my $con1 = pkg('Contrib')->new(first => 'Bobby', last => 'Bob');
$con1->save();
END { $con1->delete() };
my $con2 = pkg('Contrib')->new(first => 'Bobby', last => 'Bob');
eval { $con2->save() };
isa_ok($@, 'Krang::Contrib::DuplicateName');


# test Krang::Contrib->full_name()
my $contrib4 = pkg('Contrib')->new(prefix => 'Mr', first => 'Homer', middle => '', last => 'Simpson', email => 'homer@thepirtgroup.com');
my $name1 = 'Mr Homer Simpson';
my $name2 = 'Mr Homer Jay Simpson';
my $name3 = 'Mr Homer Jay Simpson, MD';

ok($contrib4->full_name() eq $name1, 'Krang::Contrib->full_name()');

$contrib4->middle('Jay');

ok($contrib4->full_name() eq $name2, 'Krang::Contrib->full_name()');

$contrib4->suffix('MD');

ok($contrib4->full_name() eq $name3, 'Krang::Contrib->full_name()');

$contrib4->suffix(undef);
$contrib4->middle(undef);

ok($contrib4->full_name() eq $name1, 'Krang::Contrib->full_name()');


test_image();


sub test_image {

    my $image = create_media($category);
    my $img_contrib = pkg('Contrib')->new(prefix => 'Mr', first => 'Homer', middle => '', last => 'Simpson', email => 'homer@thepirtgroup.com');

    ok(!defined($img_contrib->image()), "Krang::Contrib->image()");
    $img_contrib->image($image);
    my $returned_image = $img_contrib->image();

    ok($returned_image->isa('Krang::Media'), 'Krang::Contrib->image()');
    ok($returned_image->media_id == $image->media_id, 'Krang::Contrib->image()');

    $img_contrib->save();

    my ($contrib2) = pkg('Contrib')->find(contrib_id => $img_contrib->contrib_id());
    $returned_image = $contrib2->image();

    ok($returned_image->isa('Krang::Media'), 'Krang::Contrib->image()');
    ok($returned_image->media_id == $image->media_id, 'Krang::Contrib->image()');

    # cleanup
    $image->delete();
    $img_contrib->delete();
}



sub create_media {
    my $category = shift;


    # create a random image
    my ($x, $y);
    my $img = Imager->new(xsize => $x = (int(rand(300) + 50)),
                          ysize => $y = (int(rand(300) + 50)),
                          channels => 3,
                         );

    # fill with a random color
    $img->box(color => Imager::Color->new(map { int(rand(255)) } 1 .. 3),
              filled => 1);

    # draw some boxes and circles
    for (0 .. (int(rand(8)) + 2)) {
        if ((int(rand(2))) == 1) {
            $img->box(color =>
                      Imager::Color->new(map { int(rand(255)) } 1 .. 3),
                      xmin => (int(rand($x - ($x/2))) + 1),
                      ymin => (int(rand($y - ($y/2))) + 1),
                      xmax => (int(rand($x * 2)) + 1),
                      ymax => (int(rand($y * 2)) + 1),
                      filled => 1);
        } else {
            $img->circle(color =>
                         Imager::Color->new(map { int(rand(255)) } 1 .. 3),
                         r => (int(rand(100)) + 1),
                         x => (int(rand($x)) + 1),
                         'y' => (int(rand($y)) + 1));
        }
    }

    # pick a format
    my $format = (qw(jpg png gif))[int(rand(3))];

    $img->write(file => catfile(KrangRoot, "tmp", "tmp.$format"));
    my $fh = IO::File->new(catfile(KrangRoot, "tmp", "tmp.$format"))
      or die "Unable to open tmp/tmp.$format: $!";

    # Pick a type
    my %media_types = pkg('Pref')->get('media_type');
    my @media_type_ids = keys(%media_types);
    my $media_type_id = $media_type_ids[int(rand(scalar(@media_type_ids)))];

    # create a media object
    my $media = pkg('Media')->new(title      => get_word(),
                                  filename   => get_word() . ".$format",
                                  caption    => get_word(),
                                  filehandle => $fh,
                                  category_id => $category->category_id,
                                  media_type_id => $media_type_id,
                                  );
    eval { $media->save };
    if ($@) {
        if (ref($@) and ref($@) eq 'Krang::Media::DuplicateURL') {
            redo;
        } else {
            die $@;
        }
    }
    unlink(catfile(KrangRoot, "tmp", "tmp.$format"));


    $media->checkin();

    return $media;

}

# get a random word
BEGIN {
    my @words;
    open(WORDS, "/usr/dict/words")
      or open(WORDS, "/usr/share/dict/words")
        or die "Can't open /usr/dict/words or /usr/share/dict/words: $!";
    while (<WORDS>) {
        chomp;
        push @words, $_;
    }
    srand (time ^ $$);

    sub get_word {
        return lc $words[int(rand(scalar(@words)))];
    }
}
