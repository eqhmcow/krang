#!/usr/bin/perl -w
use Krang::ErrorHandler;
use Krang::CGI::Login;
my $app = Krang::CGI::Login->new();
$app->run();
