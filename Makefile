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
#
#   elements - rebuild test element trees in t/elements from Bricolage 
#              sources in t/eloader

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
TEST_ASSERT=1
test:
	KRANG_ROOT=`pwd` KRANG_ASSERT=$(TEST_ASSERT) perl -Ilib -we 'use Test::Harness qw(&runtests $$verbose); $$verbose=$(TEST_VERBOSE); runtests @ARGV;' $(TEST_FILES)


# setup default BENCH_NAME
BENCH_NAME  = $(shell date +'[ %D %H:%M ]')
BENCH_FILES = bench/*.pl 
bench:
	KRANG_ROOT=`pwd` perl -Ilib -MKrang::Benchmark -e 'Krang::Benchmark::start_benchmark(name => "$(BENCH_NAME)")'
	ls $(BENCH_FILES) | KRANG_ROOT=`pwd` xargs -n1 perl -Ilib

bench_clean:
	- rm bench.out

db:
	bin/krang_createdb

docs:
	cd docs && $(MAKE)

elements:
	rm -rf t/elements/Bric_Default t/elements/LA t/elements/NYM
	bin/krang_bric_eloader --set LA --xml t/eloader/LA.xml
	bin/krang_bric_eloader --set NYM --xml t/eloader/NYM.xml
	bin/krang_bric_eloader --set Bric_Default --xml t/eloader/Bric_Default.xml


.PHONY : all test clean TAGS bench docs bench_clean elements

