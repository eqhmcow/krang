#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'CGI::Debug';
pkg('CGI::Debug')->new()->run();
