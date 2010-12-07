#!/usr/bin/perl
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Login';
my $app = pkg('CGI::Login')->new();
$app->run();
