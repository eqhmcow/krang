#!/usr/bin/perl -w
use Krang::ErrorHandler;
use Krang::CGI::Status;
my $app = Krang::CGI::Status->new();
$app->run();
