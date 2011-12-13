#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 16;

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader Conf => qw(KrangRoot InstanceElementSet);
use Krang::ClassLoader 'Element';
use Krang::ClassLoader 'ElementLibrary';
use Krang::ClassLoader 'Media';
use Krang::ClassLoader 'Script';

use File::Spec::Functions qw(catdir catfile splitdir canonpath);
use FindBin qw($RealBin);

BEGIN {
    my $found;
    foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        if (InstanceElementSet eq 'TestSet1') {
            last;
        }
    }
}

# set up site/category
my $site = pkg('Site')->new(
    preview_path => './sites/test1/preview/',
    preview_url  => 'preview.testsite1.com',
    publish_path => './sites/test1/',
    url          => 'testsite1.com'
);
$site->save();
END { $site->delete(); }

# load element library
eval { pkg('ElementLibrary')->load_set(set => 'TestSet1') };
ok(!$@ => 'Load TestSet1 element set');

# create new media object
my ($category) = pkg('Category')->find(limit => 1);
die 'No categories found.' unless $category;
my $media = pkg('Media')->new(
    title         => 'Test Media',
    media_type_id => 1,
    category_id   => $category->category_id
);

# check that it returned a media object & element
ok($media, "media->new returned a media object");
ok($media->element, "media->new returned a media element");

# save the media object
my $fh;
open $fh, catfile(KrangRoot, 't', 'media', 'krang.gif');
$media->upload_file(filehandle => $fh, filename => 'krang.gif');
$media->save;
close $fh;

# verify that saving it caused element_id to be written
ok($media->element_id, "$media->save returned an element_id");

# examine its element
my $element = $media->element;
isa_ok($element->class, 'Krang::ElementClass::Media', 'element is of correct class');
is($element->element_id, $media->element_id, "element->element_id matches media->element_id");

# populate element
my $page   = $element->child('page');
my $header = $page->child('header');
$header->data('Test This Header');
is($header->data => 'Test This Header', "setting media element data works in memory");
my $story =
  pkg('Story')->new(class => "article", title => "t", slug => "s", categories => [$category]);
$story->save;
my $leadin = $page->add_child(class => 'leadin', data => $story);
is($leadin->data => $story, "test adding leadin to media element");

# make sure element->media works
is($element->media, $media, "test reaching media through element->media");

# save the media object to database and reload it
$media->save;
my $element_id = $media->element_id;
my $media_id   = $media->media_id;
my ($media_in_db) = pkg('Media')->find(media_id => $media_id);

# make sure element has been saved with correct value
ok($media_in_db, "make sure media has been written to database");
is($media_in_db->element_id => $element_id, "make sure media in database has correct element_id");
is(
    $media_in_db->element->child('page')->child('header')->data => "Test This Header",
    "media element has correct value in database"
);

# test story link
my @linked_stories = $media->linked_stories();
is(scalar @linked_stories, 1, "make sure linked_stories returns exactly one story");
is($linked_stories[0], $story, "make sure it's the correct story");
$story->delete;

# delete media file & element
$media->delete;
ok(!pkg('Media')->find(media_id => $media_id), "media can be deleted");
eval { pkg('Element')->load(element_id => $element_id, object => $media) };
ok($@, "deleting media deletes element");
