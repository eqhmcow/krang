#!/usr/bin/perl -w
use Krang::ErrorHandler;
use Krang::CGI::Group;
my $app = Krang::CGI::Group->new();
$app->run();
