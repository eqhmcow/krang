#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::User';
my $app = pkg('CGI::User')->new(
    PARAMS => {
        PACKAGE_PERMISSIONS => [qw(admin_users admin_users_limited)],
    }
)->run();
