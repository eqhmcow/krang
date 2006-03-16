#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);

use Krang::ClassLoader 'CGI::Contrib';
my $app = pkg('CGI::Contrib')->new(
    PARAMS => {
        PACKAGE_PERMISSIONS => [qw(admin_contribs)],
    },
)->run();
