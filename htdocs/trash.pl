#!/usr/bin/env perl
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Trash';
pkg('CGI::Trash')->new(
    PARAMS => {
        PACKAGE_PERMISSIONS => [qw(may_view_trash)],
        RUNMODE_PERMISSIONS => {delete_checked => [qw(admin_delete)]}
    },
)->run();
