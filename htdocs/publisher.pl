#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Publisher';
my $app = pkg('CGI::Publisher')->new();
$app->run();
