#!/usr/bin/perl
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::DeskAdmin';
my $app = pkg('CGI::DeskAdmin')->new(
    PARAMS => {
        PACKAGE_PERMISSIONS => [qw(admin_desks)],
    },
)->run();
