use strict;
use warnings;
use Krang;
use Krang::Conf qw (KrangRoot);
use File::Spec::Functions qw(catdir catfile);
use FileHandle;
use Benchmark;
use Krang::Media;

my $new_media = sub {
    my $media = Krang::Media->new(title => 'test media object', category_id => 1);
    my $filepath = catfile(KrangRoot,'t','media','krang.jpg');
    my $fh = new FileHandle $filepath;
    $media->upload_file(filename => 'krang.jpg', filehandle => $fh);
    $media->save(); 
};

my $count = 11000;
print "Creating $count new media objects...\n";
my $t = timeit($count, $new_media );
print "Took: ".timestr($t)."\n";
