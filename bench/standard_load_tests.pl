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
my $site;
($site) = Krang::Site->find( limit => 1 );

my $found_site = $site ? 1 : 0;

$site = Krang::Site->new(preview_path => '/standard_bench_preview',
                            preview_url => 'preview.standard_bench.com',
                            publish_path => '/standard_bench_publish',
                            url => 'standard_bench.com') if not $site;
$site->save();
END { $site->delete() if not $found_site };

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
    $media = Krang::Media->new(title => 'test media object', category_id => $category_id, media_type_id=>1);
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

###################################
$i = 0;
my $div = $media_upload_count / 5;
run_benchmark(  module => 'Krang::Media',
                name   => "find with limit $div, offset",
                count => 100,
                code =>
            sub {
                Krang::Media->find( limit => $div, offset => $i );
                $i = $i + $div;
                $i = 0 if ($i > $media_upload_count);
            });
###################################

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

my @siteurls = ('collects.kra:8080', 'shuttered.kra:8080', 'vaticanizes.kra:8080');

foreach my $siteurl ( @siteurls ) {
# now update site preview and publish path for this installation
    my ($site1) = Krang::Site->find( url => $siteurl );
    $siteurl =~ s/:8080//;
    $site1->preview_path( catdir(KrangRoot, "tmp", $siteurl.'_preview') );
    $site1->publish_path( catdir(KrangRoot, "tmp", $siteurl.'_publish') );
    $site1->save();
}

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
my $krang_publish = catfile(KrangRoot, 'bin', 'krang_publish');
$i = 0;
my $publisher = Krang::Publisher->new;
run_benchmark(  module => 'Krang::Story',
                name => 'Publish 100 stories, one at a time',
                count => 100,
                code => sub {
                    $publisher->publish_story(story => $found_stories[$i++]);
                } ); 
##############################################################

$done = 0;
my $sids = join(',', map{ $_->story_id } @found_stories);
run_benchmark(  module => 'Krang::Story',
                name => 'Publish 100 stories at a time',
                count => 100,
                code => sub {
                    if (not $done) {
                        `$krang_publish --story_id $sids`;
                        $done = 1;
} } );
 
##############################################################
$done = 0;
my $story_count = Krang::Story->find( count => 1 );

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
