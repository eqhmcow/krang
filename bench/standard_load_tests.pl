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
use File::Spec::Functions qw( catfile );

my $media_upload_count = 500;

my $filepath = catfile(KrangRoot,'t','media','krang.jpg');
my $filepath2 = catfile(KrangRoot,'t','media','krang.gif');
my $media;

# set up site and category
my $site = Krang::Site->new(preview_path => '/standard_bench_preview',
                            preview_url => 'preview.standard_bench.com',
                            publish_path => '/standard_bench_publish',
                            url => 'standard_bench.com');
$site->save();
END { $site->delete() };

my ($category) = Krang::Category->find(site_id => $site->site_id());
my $category_id = $category->category_id();

##########################################################
my $i = 0;
my @media_ids;

run_benchmark(module => 'Krang::Media',
              name   => 'new, upload, save',
              count  => $media_upload_count,               
              code   =>
sub {
    $media = Krang::Media->new(title => 'test media object', category_id => $category_id);
    if ( $i % 2 ) {
        my $fh = new FileHandle $filepath;
        $media->upload_file(filename => $i++."krang.jpg", filehandle => $fh);
    } else {
        my $fh = new FileHandle $filepath2;
        $media->upload_file(filename => $i++."krang.gif", filehandle => $fh);
    }
    $media->save();
    push (@media_ids, $media->media_id);
} );

###########################################################
$i = 0;

run_benchmark(  module => 'Krang::Media',
                name   => 'delete',
                count  => $media_upload_count,
                code   =>
    sub { Krang::Media->delete( $media_ids[$i++]) } );

#############################################################

my $krang_import = catfile(KrangRoot, 'bin', 'krang_import');
my $story_kds = catfile(KrangRoot, 'bench', 'load', 'base', 'stories.kds');

my $done = 0;

run_benchmark(  module => 'Krang::DataSet',
                name   => 'Import 200 stories',
                count  => 200,
                code   => sub { 
                    if (not $done) {
                        `$krang_import $story_kds`;
                        $done = 1;
                    } } );

############################################################
my @found_stories = Krang::Story->find( limit => 100 );
$i = 0;
                                                                              
run_benchmark(  module => 'Krang::Story',
                name => 'Find story by title',
                count => 100,
                code => sub {
                    my $S = Krang::Story->find( title => $found_stories[$i++]->title );
                } );

##############################################################
$done = 0;
my $story_count = Krang::Story->find( count => 1 );
my $krang_publish = catfile(KrangRoot, 'bin', 'krang_publish');

run_benchmark(  module => 'Krang::Publisher',
                name   => "Publish entire site ($story_count stories)",
                count => $story_count,
                code => sub {
                    if (not $done) {
                        `$krang_publish --everything --increment 200`;
                        $done = 1;
                    }
                } );
###############################################################
