#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Schedule';
my $app = pkg('CGI::Schedule')->new();
$app->run();
