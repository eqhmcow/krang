#!/usr/bin/perl -w
use Krang::ErrorHandler;
use Krang::CGI::MyPref;
my $app = Krang::CGI::MyPref->new();
$app->run();
