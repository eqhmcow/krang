# Krang master Makefile.  The following targets are supported:
#
#   all   - runs ext
#
#   ext   - builds the modules in ext-src and installs them in ext-lib
# 
#   test  - runs the test suite
#
#   TAGS  - builds an etags file from Krang module sources
#
#   clean - cleans up ext-src and ext-lib so that a subsequent make ext
#           will rebuild all libraries.
#
#   bench - runs the benchmark scripts in bench/
#
#   db    - recreates databases by calling bin/krang_createdb
#
#   docs  - build HTML docs from pod

all: ext

ext:
	cd ext-src && $(MAKE)

clean:	bench_clean
	cd ext-src && $(MAKE) clean
	cd ext-lib && rm -rf 

TAGS:	
	find -name '*.pm' | etags --language="perl" --regex='/[ \\t]*[A-Za-z]+::[a-zA-Z:]+/' -

# test section, ripped from Makefile.PL output
TEST_VERBOSE=0
TEST_FILES = t/*.t
test:
	KRANG_ROOT=`pwd` perl -Ilib -Iext-lib -we 'use Test::Harness qw(&runtests $$verbose); $$verbose=$(TEST_VERBOSE); runtests @ARGV;' $(TEST_FILES)


# setup default BENCH_NAME
BENCH_NAME  = $(shell date +'[ %D %H:%M ]')
BENCH_FILES = bench/*.pl 
bench:
	KRANG_ROOT=`pwd` perl -Ilib -Iext-lib -MKrang::Benchmark -e 'Krang::Benchmark::start_benchmark(name => "$(BENCH_NAME)")'
	ls $(BENCH_FILES) | KRANG_ROOT=`pwd` xargs -n1 perl -Ilib -Iext-lib

bench_clean:
	- rm bench.out

db:
	bin/krang_createdb

docs:
	cd docs && $(MAKE)

.PHONY : all test clean TAGS bench docs bench_clean

