#!/usr/bin/perl -w
use Krang::ErrorHandler;
use Krang::CGI::Site;
my $app = Krang::CGI::Site->new();
$app->run();
