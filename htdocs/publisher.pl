#!/usr/bin/perl -w
use Krang::ErrorHandler;
use Krang::CGI::Publisher;
my $app = Krang::CGI::Publisher->new();
$app->run();
