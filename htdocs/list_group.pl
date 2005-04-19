#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::ListGroup';
my $app = pkg('CGI::ListGroup')->new();
$app->run();
