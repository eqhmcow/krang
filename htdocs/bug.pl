#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Bugzilla';
my $app = pkg('CGI::Bugzilla')->new();
$app->run();
