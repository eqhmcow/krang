 
# test section, ripped from Makefile.PL output
TEST_VERBOSE=0
TEST_FILES = t/*.t

all: ext

ext:
	cd ext-src && $(MAKE)

clean:
	cd ext-src && $(MAKE) clean

TAGS:	
	find -name '*.pm' | etags --language="perl" --regex='/[ \\t]*[A-Za-z]+::[a-zA-Z:]+/' -

test:
	KRANG_ROOT=`pwd` perl -Ilib -Iext-lib -we 'use Test::Harness qw(&runtests $$verbose); $$verbose=$(TEST_VERBOSE); runtests @ARGV;' $(TEST_FILES)

.PHONY : all test clean TAGS

