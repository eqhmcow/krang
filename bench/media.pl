use strict;
use warnings;
use Krang::Script;
use Krang::Conf qw (KrangRoot);
use File::Spec::Functions qw(catdir catfile);
use FileHandle;
use Krang::Benchmark qw(run_benchmark);
use Krang::Media;
use Krang::Category;
use Krang::Site;
use File::Path;

my $count = 1000;
my $filepath = catfile(KrangRoot,'t','media','krang.jpg');
my $media;

# set up site and category
my $site = Krang::Site->new(preview_path => '/media_bench_preview',
                            preview_url => 'preview.media_bench.com',
                            publish_path => '/media_bench_publish',
                            url => 'media_bench.com');
$site->save();
#END { $site->delete() };

my ($category) = Krang::Category->find(site_id => $site->site_id());
my $category_id = $category->category_id();
#END { $category->delete() };

my $i = 0;
run_benchmark(module => 'Krang::Media',
              name   => 'new, upload, save',
              count  => $count,               
              code   =>
sub {
    $media = Krang::Media->new(title => 'test media object', category_id => $category_id);
    my $fh = new FileHandle $filepath;
    $media->upload_file(filename => $i++."krang.jpg", filehandle => $fh);
    $media->save();
} );

###################################

my @media_object;

$i = $media->media_id() - ($count - 1);
run_benchmark(module => 'Krang::Media',
              name   => 'find',
              count  => $count,               
              code   =>
         sub {
             push @media_object, Krang::Media->find(media_id => $i++);
         });

###################################

$i = 0;
run_benchmark(module => 'Krang::Media',
              name   => 'checkout',
              count  => $count,               
              code   => 
         sub {
            $media_object[$i++]->checkout();
         });

###################################

$i = 0;
run_benchmark(module => 'Krang::Media',
              name   => 'create new version',
              count  => $count,               
              code   =>
         sub {
            my $fh = new FileHandle $filepath;
            $media_object[$i]->upload_file(filename => $i."krang.jpg", filehandle => $fh);
            $media_object[$i++]->save();
         });

###################################

$i = 0;
run_benchmark(  module => 'Krang::Media',
                name => 'create thumbnail, return thumnail path',
                count => $count,
                code =>
                sub {
                    $media_object[$i++]->thumbnail_path(); 
                });
###################################

$i = 0;
run_benchmark(module => 'Krang::Media',
              name   => 'revert and save',
              count  => $count,               
              code   =>
         sub {
            $media_object[$i]->revert(1);
            $media_object[$i++]->save();
         });

###################################

###################################

$i = 0;
run_benchmark(module => 'Krang::Media',
              name   => 'checkin',
              count  => $count,               
              code   =>
         sub {
            $media_object[$i++]->checkin();
         });

###################################

###################################

$i = 0;
run_benchmark(module => 'Krang::Media',
              name   => 'delete',
              count  => $count,               
              code   =>
         sub {
            $media_object[$i++]->delete();
         });

###################################

rmtree(catdir(KrangRoot,'data','media')); 


