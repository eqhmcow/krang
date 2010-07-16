#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'CGI::Bugzilla';
pkg('CGI::Bugzilla')->new()->run();
