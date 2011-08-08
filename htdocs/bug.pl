#!/usr/bin/env perl
use warnings;
use CGI;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'CGI::Bugzilla';

pkg('CGI::Bugzilla')->new()->run();
