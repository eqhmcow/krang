#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Media::BulkUpload';
my $app = pkg('CGI::Media::BulkUpload')->new(
    PARAMS => {
        PACKAGE_ASSETS => { media => [qw(edit)] },
    },
)->run();

