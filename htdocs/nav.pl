#!/usr/bin/perl
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'CGI::Nav';
pkg('CGI::Nav')->new()->run();
