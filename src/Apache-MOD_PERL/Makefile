## $Id$
## Makefile to build Apache with mod_perl
##
## By Jesse Erlbaum <jesse@erlbaum.net>
## Originally Created: December 2000



#### User-configurable variables
####  Change these as necessary!


# What are the names of the packages to build (not including ".tar.gz")
APACHE_PACKAGE		= apache_1.3.29
MODPERL_PACKAGE		= mod_perl-1.29


# Where do we put the final builds?
PERL_BUILD		= perl_parts
APACHE_BUILD		= apache

TARBALL_FILE		= Apache-MOD_PERL.tar.gz

#### END User-configurable vars




###############################
####  Public Make Targets  ####
###############################

default:
	@echo ""
	@echo "TO BUILD APACHE:"
	@echo "  Choose make mode:  build, tarball, clean, distclean"
	@echo "  Generally, you will want to 'make tarball' or 'make build'."
	@echo ""


build: prep_build build_modperl build_apache


tarball: build
	@echo "#### Creating tarball for distribution..."
	tar -czf $(TARBALL_FILE) $(PERL_BUILD) $(APACHE_BUILD)
	@echo "Tarfile '$(TARBALL_FILE)' created."


clean:
	@echo "#### Cleaning MOD_PERL work directory..."
	-cd $(MODPERL_PACKAGE) && make distclean

	@echo "#### Cleaning Apache work directory..."
	-cd $(APACHE_PACKAGE) && make distclean

	@echo "#### Cleaning up build areas..."
	rm -Rf $(PERL_BUILD)/*
	rm -Rf $(APACHE_BUILD)/*


distclean:
	@echo "#### Blowing away working and build directories..."
	-rm -Rf $(MODPERL_PACKAGE)
	-rm -Rf $(APACHE_PACKAGE)
	-rm -Rf $(PERL_BUILD)
	-rm -Rf $(APACHE_BUILD)

	@echo "#### Removing tarball..."
	-rm $(TARBALL_FILE)



###########################
####  Private targets  ####
###########################

prep_build:
	@echo "#### Preparing working directories..."
	[ ! -d $(MODPERL_PACKAGE) ] && tar -xzf $(MODPERL_PACKAGE).tar.gz
	[ ! -d $(APACHE_PACKAGE) ] && tar -xzf $(APACHE_PACKAGE).tar.gz

	@echo "#### Creating build directories..."
	-mkdir $(PERL_BUILD)
	-mkdir $(APACHE_BUILD)


build_apache:
	@echo "#### Building Apache parts..."
	BUILD_PWD=`pwd` && cd $(APACHE_PACKAGE) && PERL5LIB=$$BUILD_PWD/$(PERL_BUILD)/lib/site_perl:$$PERL5LIB ./configure \
	  --prefix=../$(APACHE_BUILD) \
	  --activate-module=src/modules/perl/libperl.a \
	  --disable-shared=perl \
	  --enable-module=rewrite --enable-shared=rewrite \
	  --enable-module=proxy   --enable-shared=proxy \
	  --enable-module=mime_magic   --enable-shared=mime_magic \
	&& \
	make && \
	make install


build_modperl:
	@echo "#### Building MOD_PERL parts..."
	BUILD_PWD=`pwd` && cd $(MODPERL_PACKAGE) && perl Makefile.PL \
	  PREFIX=$$BUILD_PWD/$(PERL_BUILD) \
	  INSTALLMAN3DIR=$$BUILD_PWD/$(PERL_BUILD)/man/man3 \
	  APACHE_SRC=../$(APACHE_PACKAGE)/src \
	  DO_HTTPD=1 \
	  USE_APACI=1 \
	  PREP_HTTPD=1 \
	  EVERYTHING=1 && \
	make && \
	make install

