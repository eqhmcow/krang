#!/usr/bin/perl -w

##########################################
####  MODULES TO PRE-LOAD INTO KRANG  ####
##########################################

use Krang::ErrorHandler;
use DBI;
use Apache::DBI;
use HTML::Template;
use CGI;


print STDERR "Krang Pre-load complete.\n";

1;
