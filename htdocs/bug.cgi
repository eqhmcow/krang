#!/usr/bin/perl -w
use Krang::ErrorHandler;
use Krang::CGI::Bugzilla;
my $app = Krang::CGI::Bugzilla->new();
$app->run();
