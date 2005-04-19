#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::DeskAdmin';
my $app = pkg('CGI::DeskAdmin')->new();
$app->run();
