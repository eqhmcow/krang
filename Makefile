# Krang master Makefile.  The following targets are supported: 
#
#   all   - Show help text
#
#   test  - runs the test suite
#
#   TAGS  - builds an etags file from Krang module sources
#
#   clean - cleans up benchmarks
#
#   bench - runs the benchmark scripts in bench/
#
#   db    - recreates databases by calling bin/krang_createdb
#
#   docs  - build HTML docs from pod
#
#   elements - rebuild test element trees in t/elements from Bricolage 
#              sources in t/eloader
#
#   dist  - build a Krang distribution for release
#
#   install - install Krang from a distribution
#
#   upgrade - upgrade an existing Krang installation from a distribution
#


all:
	@echo "Krang Makefile:  You're probably looking for 'make db' or 'make test'"

clean:	bench_clean

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
	bin/krang_createdb --destroy

docs:
	cd docs && $(MAKE)

elements:
	rm -rf t/elements/Bric_Default t/elements/LA t/elements/NYM
	bin/krang_bric_eloader --set LA --xml t/eloader/LA.xml
	bin/krang_bric_eloader --set NYM --xml t/eloader/NYM.xml
	bin/krang_bric_eloader --set Bric_Default --xml t/eloader/Bric_Default.xml

dist:
	@echo "Use bin/krang_makedist to make a release."
	@bin/krang_makedist --help


install:
	@echo "Use bin/krang_install to install."
	@bin/krang_install --help


upgrade:
	@echo "Use bin/krang_upgrade to upgrade."
	@bin/krang_upgrade --help


.PHONY : all test clean TAGS bench docs bench_clean elements dist install upgrade

