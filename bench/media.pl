use strict;
use warnings;
use Krang;
use Krang::Conf qw (KrangRoot);
use File::Spec::Functions qw(catdir catfile);
use FileHandle;
use Benchmark;
use Krang::Media;
use File::Path;

my $count = 1000;
my $filepath = catfile(KrangRoot,'t','media','krang.jpg');
my $media;

print "\n", "=" x 79,"\nCreating $count new media objects, uploading media files, and saving...\n";

timethis($count, sub {
    $media = Krang::Media->new(title => 'test media object', category_id => 1);
    my $fh = new FileHandle $filepath;
    $media->upload_file(filename => 'krang.jpg', filehandle => $fh);
    $media->save();
} );

print "=" x 79, "\n\n";


###################################

my @media_object;

print "\n", "=" x 79,"\nLoading $count media objects into memory by id...\n";
my $i = $media->media_id() - ($count - 1);
timethis($count,
         sub {
             push @media_object, Krang::Media->find(media_id => $i++);
         });
print "=" x 79, "\n\n";

###################################

print "\n", "=" x 79,"\nChecking out $count media objects ...\n";

$i = 0;
timethis($count,
         sub {
            $media_object[$i++]->checkout();
         });
print "=" x 79, "\n\n";

###################################

print "\n", "=" x 79,"\nUploading new media file for each of $count media objects, saving (creating second versions)...\n";

$i = 0;
timethis($count,
         sub {
            $media_object[$i]->prepare_for_edit();
            my $fh = new FileHandle $filepath;
            $media_object[$i]->upload_file(filename => 'krang.jpg', filehandle => $fh);
            $media_object[$i++]->save();
         });
print "=" x 79, "\n\n";

###################################

###################################

print "\n", "=" x 79,"\nReverting $count media objects from version 1, saving...\n";

$i = 0;
timethis($count,
         sub {
            $media_object[$i]->prepare_for_edit();
            $media_object[$i]->revert(1);
            $media_object[$i++]->save();
         });
print "=" x 79, "\n\n";

###################################

###################################
print "\n", "=" x 79,"\nChecking in $count media objects ...\n";

$i = 0;
timethis($count,
         sub {
            $media_object[$i++]->checkin();
         });
print "=" x 79, "\n\n";

###################################

###################################

print "\n", "=" x 79,"\nDeleting $count media objects...\n";

$i = 0;
timethis($count,
         sub {
            $media_object[$i++]->delete();
         });
print "=" x 79, "\n\n";

###################################

rmtree(catdir(KrangRoot,'data','media')); 
