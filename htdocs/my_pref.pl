#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::MyPref';
my $app = pkg('CGI::MyPref')->new();
$app->run();
