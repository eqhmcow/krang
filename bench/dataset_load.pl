#!/usr/bin/perl

use strict;
use warnings;

use File::Spec::Functions qw(catfile);

use Krang::Script;
use Krang::Benchmark qw(run_benchmark);
use Krang::Conf qw(KrangRoot);
use Krang::Script;
use Krang::DataSet;
use Krang::Site;

my $site;

($site) = Krang::Site->find ( limit => 1 );

die "Unable to find site - exiting.\n" unless ($site);

my $krang_export = catfile(KrangRoot, 'bin', 'krang_export');
my $test_kds     = catfile(KrangRoot, 'bench', 'dataset_test_data.kds');



my $story_count = Krang::Story->find( count => 1 );
my $media_count = Krang::Media->find( count => 1 );
my $category_count = Krang::Category->find( count => 1 );
my $contrib_count = Krang::Contrib->find( count => 1 );

my $totals = sprintf("%i st, %i med, %i cats, %i cntrb", $story_count, $media_count, $category_count, $contrib_count);

############################################################
## Export
##

my $done = 0;
run_benchmark( module => 'Krang::DataSet',
               name   => "Export everything ($totals)",
               count  => $story_count,
               code   => sub {
                   if (not $done) {
                       `$krang_export --output $test_kds --overwrite --everything`;
                       $done = 1;
                   }
               }
             );


############################################################
## new()
##

unless (-e $test_kds) {
    die "Error:  Need a working .kds file at '$test_kds'.\n";
}


my $dataset;
$done = 0;

run_benchmark(module => 'Krang::Dataset',
              name   => "new ($totals)",
              count  => $story_count,
              code   =>
              sub {
                  if (not $done) {
                      $dataset = Krang::DataSet->new(path => $test_kds);
                      $done = 1;
                  }
              }
             );


############################################################
## list()

$done = 0;
my @objects;
my %count;

run_benchmark(module => 'Krang::Dataset',
              name   => "list ($totals)",
              count  => $story_count,
              code =>
              sub {
                  if (not $done) {
                      @objects = $dataset->list();
                      $done = 1;
                  }
              }
             );

map { $count{$_->[0]}++ } @objects;
use Data::Dumper;
print Dumper(\%count);


############################################################
## import()

$done = 0;
run_benchmark(module => 'Krang::Dataset',
              name   => "import_all ($totals)",
              count  => $story_count,
              code =>
              sub {
                  if (not $done) {
                      @objects = $dataset->import_all();
                      $done = 1;
                  }
              }
             );




unlink $test_kds;


