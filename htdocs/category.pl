#!/usr/bin/env perl
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Category';
pkg('CGI::Category')->new(
    PARAMS => {
        PACKAGE_PERMISSIONS => [qw(admin_categories)],
    }
)->run();
