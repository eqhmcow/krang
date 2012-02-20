# Krang master Makefile.  The following targets are supported: 
#
#   all   - Show help text  
#
#   test  - runs the test suite
#
#   test  - runs the test suite and put the results into a TAP archive file
#
#   TAGS  - builds an etags file from Krang module sources
#
#   clean - cleans up benchmarks
#
#   bench - runs the benchmark scripts in bench/
#
#   db    - recreates databases by calling bin/krang_createdb
#
#   db_q  - recreates databases by calling bin/krang_createdb with no prompt
#
#   restart  - restarts Krang 
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

ifdef DISPLAY
notify = notify-send -i $(KRANG_ROOT)/data/notify.png --urgency normal --expire-time 10000 --hint=int:transient:1 $(1) $(2)
endif

all:
	@echo "No default make target."

build: clean
	bin/krang_build
	$(call notify, "Krang build finished", "at $(KRANG_ROOT)")

dist:
	bin/krang_makedist
	$(call notify, "Krang Dist created")

clean:	bench_clean
	- find lib/ -mindepth 1 -maxdepth 1 | grep -v Krang | grep -v .svn | grep -v bin | grep -v '.cvsignore' | grep -v '^lib/Devel/CheckLib.pm' | grep -v '^lib/Devel' | xargs rm -rf
	- find apache/ -mindepth 1 -maxdepth 1 | grep -v .svn | grep -v '.cvsignore' | xargs rm -rf
	- rm -f data/build.db
	- rm -f htdocs/data
	- rm -f htdocs/tmp
	- rm -rf conf/ssl.crl
	- rm -rf conf/ssl.crt
	- rm -rf conf/ssl.csr
	- rm -rf conf/ssl.key
	- rm -rf conf/ssl.prm
	- $(call notify, "Krang cleaned", "at $(KRANG_ROOT)")

TAGS:	
	find -name '*.pm' | etags --language="perl" --regex='/[ \\t]*[A-Za-z]+::[a-zA-Z:]+/' -

# test section, ripped from Makefile.PL output
TEST_VERBOSE = 0
TEST_FILES = 0
test:
	bin/krang_test --verbose-i="$(TEST_VERBOSE)" --files="$(TEST_FILES)"
	$(call notify, "Krang test finished", "at $(KRANG_ROOT)")

test_archive:
	bin/krang_test --verbose-i="$(TEST_VERBOSE)" --files="$(TEST_FILES)" --tap-archive
	$(call notify, "Krang test finished", "at $(KRANG_ROOT)")

# setup default BENCH_NAME
BENCH_NAME  = $(shell date +'[ %D %H:%M ]')
BENCH_FILES = bench/*.pl 
bench:
	KRANG_ROOT=`pwd` perl -Ilib -MKrang::Benchmark -e 'Krang::Benchmark::start_benchmark(name => "$(BENCH_NAME)")'
	ls $(BENCH_FILES) | KRANG_ROOT=`pwd` xargs -n1 perl -Ilib

bench_clean:
	- rm -f bench.out

db:
	bin/krang_createdb --destroy --all
	$(call notify, "Krang DB created", "at $(KRANG_ROOT)")

db_q:
	bin/krang_createdb --destroy --all --no_prompt
	$(call notify, "Krang DB created", "at $(KRANG_ROOT)")

restart:
	bin/krang_ctl restart
	$(call notify, "Krang restarted", "at $(KRANG_ROOT)")

docs:
	cd docs && $(MAKE)

elements:
	rm -rf t/elements/Bric_Default t/elements/LA t/elements/NYM
	bin/krang_bric_eloader --set LA --xml t/eloader/LA.xml
	bin/krang_bric_eloader --set NYM --xml t/eloader/NYM.xml
	bin/krang_bric_eloader --set Bric_Default --xml t/eloader/Bric_Default.xml

install:
	@echo "Use bin/krang_install to install."
	@bin/krang_install --help


upgrade:
	@echo "Use bin/krang_upgrade to upgrade."
	@bin/krang_upgrade --help

TIDY_ARGS = --backup-and-modify-in-place --indent-columns=4 --cuddled-else --maximum-line-length=100 --nooutdent-long-quotes --paren-tightness=2 --brace-tightness=2 --square-bracket-tightness=2
tidy:
	- find lib/Krang/ -name '*.pm' | xargs perltidy $(TIDY_ARGS)
	- find t/ -name '*.t' | xargs perltidy $(TIDY_ARGS)
	- perltidy $(TIDY_ARGS) bin/*

tidy_modified:
	svn -q status | grep '^\(M\|A\).*\.\(pm\|pl\|t\)$$' | cut -c 8- | xargs perltidy $(TIDY_ARGS)

.PHONY : all dist test clean TAGS bench docs bench_clean elements install upgrade build

