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

# test section, ripped from Makefile.PL output
TEST_VERBOSE=0
TEST_FILES = t/*.t

all: ext

ext:
	cd ext-src && $(MAKE)

clean:
	cd ext-src && $(MAKE) clean
	cd ext-lib && rm -rf 

TAGS:	
	find -name '*.pm' | etags --language="perl" --regex='/[ \\t]*[A-Za-z]+::[a-zA-Z:]+/' -

test:
	KRANG_ROOT=`pwd` perl -Ilib -Iext-lib -we 'use Test::Harness qw(&runtests $$verbose); $$verbose=$(TEST_VERBOSE); runtests @ARGV;' $(TEST_FILES)

bench:
	KRANG_ROOT=`pwd` perl -Ilib -Iext-lib -we 'while($$_ = shift) { do $$_ or die "$$_ : $$!" }' bench/*.pl

.PHONY : all test clean TAGS bench

