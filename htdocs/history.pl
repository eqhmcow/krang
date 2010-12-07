#!/usr/bin/perl
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::History';
pkg('CGI::History')->new()->run();
