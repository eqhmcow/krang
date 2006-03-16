#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Group';
my $app = pkg('CGI::Group')->new(
    PARAMS => {
        PACKAGE_PERMISSIONS => [qw(admin_groups)],
    },
)->run();
