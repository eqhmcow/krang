#!/usr/bin/perl

use strict;
use warnings;

use File::Spec::Functions qw(catfile);

use Krang::Script;
use Krang::Benchmark qw(run_benchmark);
use Krang::Conf qw(KrangRoot);
use Krang::Script;
use Krang::DataSet;


# Note - this benchmark suite assumes that the desired data is already exported.

my $story_kds = catfile(KrangRoot, 'export.kds');

unless (-e $story_kds) {
    die "Error:  Need a working .kds file at '$story_kds'.\n";
}

my $dataset;
my %count;
my @objects;

run_benchmark(module => 'Krang::Dataset',
              name   => 'new',
              count  => 1,
              code   =>
              sub {
                  $dataset = Krang::DataSet->new(path => $story_kds);
              }
             );


run_benchmark(module => 'Krang::Dataset',
              name   => 'list',
              count  => 1,
              code =>
              sub {
                  @objects = $dataset->list();
              }
             );

map { $count{$_->[0]}++ } @objects;

use Data::Dumper;

print Dumper(\%count);

run_benchmark(module => 'Krang::Dataset',
              name   => 'import_all',
              count  => 1,
              code =>
              sub {
                  @objects = $dataset->import_all();
              }
             );





