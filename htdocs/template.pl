#!/usr/bin/perl -w
use Krang::ErrorHandler;
use Krang::CGI::Template;
my $app = Krang::CGI::Template->new();
$app->run();
