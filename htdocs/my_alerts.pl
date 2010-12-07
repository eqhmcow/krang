#!/usr/bin/perl
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::MyAlerts';
my $app = pkg('CGI::MyAlerts')->new();
$app->run();
