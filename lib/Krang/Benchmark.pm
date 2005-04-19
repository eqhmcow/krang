package Krang::Benchmark;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Time::HiRes qw(time);
use Carp qw(croak);

use Krang::ClassLoader Conf => qw(KrangRoot);
use File::Spec::Functions qw(catfile);

require Exporter;
our @ISA = ('Exporter');
our @EXPORT_OK = ('run_benchmark');

=head1 NAME

Krang::Benchmark - manages the running of benchmarks scripts

=head1 SYNOPSIS

To create a new benchmark script, create a new .pl file in F<bench/>:

  use Krang::ClassLoader Benchmark => qw(run_benchmark);

  run_benchmark(module => "Krang::Foo",
                name   => "name of benchmark here",
                count  => 1000,
                code   => sub { "some code to benchmark here" });

  run_benchmark(module => "Krang::Foo",
                name   => "name of another benchmark here",
                count  => 1000,
                code   => sub { "some code to benchmark here" });

To perform a benchmark run:

  make bench

If you want to name your benchmark run for later reference:

  make bench BENCH_NAME=some_name_here

If you want to run just one benchmark script:

  make bench BENCH_FILES=bench/file.pl

After doing at least two runs, use krang_bench to perform benchmark
analysis between the last two runs:

  bin/krang_bench

Or pass in run names to do arbitrary comparisions:

  bin/krang_bench name1 name2

=head1 DESCRIPTION

This module manages benchmarking for Krang, run using "make bench".
This module works like the standard L<Benchmark> module with a couple
differences.  First, it only cares about wallclock time, since
per-process CPU time is useless for a database application.  Second,
it dumps the results to a file called 'bench.out'.  This file can then
be used to compare benchmark results from different versions of Krang,
different data loads or across different machines.  For analysis, see
the F<bin/krang_bench> program.

=head1 INTERFACE

=over

=item run_benchmark

This subroutine is available for export.  Calling it runs a single
benchmark.  It requires the following named parameters:

=over

=item module

The name of the module being benchmarked.

=item name

The name of the benchmark.  This must be unique among benchmarks for
this module.  Idealy, it should give the user an idea of what
functionality is being tested.  For example, "save".

=item count

How many times to run the code being benchmarked.  Ideally, look for a
number of runs that completes within a few seconds.

=item code

The code to run.  Must be a reference to a subroutine.

=back

=cut

sub run_benchmark {
    my %arg = @_;
    croak("Invalid call to run_benchmark, missing required keys")
      unless exists $arg{module} and 
             exists $arg{name}   and
             exists $arg{count}  and
             exists $arg{code};
    croak("Invalid call to run_benchmark, count must be a positive integer")
      unless $arg{count} =~ /^\d+$/ and $arg{count};

    # output run header for user
    print "#" x 79, "\n", <<END;
  Module       : $arg{module}
  Benchmark    : $arg{name}
  Count        : $arg{count}
END

    # run code count times, getting timestamps on each side
    my $code  = $arg{code};
    my $count = $arg{count};
    my ($start, $end);
    $start = time;
    for (1 .. $count) { &$code; }
    $end   = time;

    my $time = $end - $start;

    my $ops = sprintf("%.2f", $arg{count} / $time);
    my $ftime = sprintf("%.2f", $time);
    
    # print results for user
    print <<END, "#" x 79, "\n\n";
  Runtime      : $ftime seconds ($ops iter/sec)
END

    # record time in bench.out for analysis later
    open(BENCH, ">>", catfile(KrangRoot, "bench.out"))
      or die "Unable to open bench.out; $!";
    $arg{module} =~ tr/\t\n/ /;
    $arg{name}   =~ tr/\t\n/ /;
    print BENCH "-\t$arg{module}\t$arg{name}\t$arg{count}\t$time\n";
    close BENCH;

    return $time;
}

=item start_benchmark(name => $name)

Starts a new benchmark in F<bench.out>.  This is usually called by
C<make bench> to signify the start of a new benchmark run.  The name
argument is required and will be used as the name of the benchmark.

=cut

sub start_benchmark {
    my %arg = @_;
    croak("Invalid call to start_benchmark, missing name")
      unless exists $arg{name};

    open(BENCH, ">>", catfile(KrangRoot, "bench.out"))
      or die "Unable to open bench.out; $!";
    $arg{name}   =~ tr/\t\n/ /;
    print BENCH "!\t$arg{name}\n";
    close BENCH;
}

=back

=head1 TODO

=over

=back

=cut

1;
