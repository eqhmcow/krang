#!/usr/bin/env perl
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI';
my $app = pkg('CGI')->new();
$app->run();
