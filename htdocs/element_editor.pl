#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::ElementEditor';
my $app = pkg('CGI::ElementEditor')->new();
$app->run();
