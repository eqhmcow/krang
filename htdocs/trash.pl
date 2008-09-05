#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Trash';
pkg('CGI::Trash')->new(
    PARAMS => {
        RUNMODE_PERMISSIONS => { delete_checked => [qw(admin_delete)] }
    },
)->run();
