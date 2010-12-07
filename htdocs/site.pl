#!/usr/bin/perl
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Site';
my $app = pkg('CGI::Site')->new(
    PARAMS => {
        PACKAGE_PERMISSIONS => [qw(admin_sites)],
    },
)->run();
