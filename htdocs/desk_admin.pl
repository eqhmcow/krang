#!/usr/bin/perl -w
use Krang::ErrorHandler;
use Krang::CGI::DeskAdmin;
my $app = Krang::CGI::DeskAdmin->new();
$app->run();
