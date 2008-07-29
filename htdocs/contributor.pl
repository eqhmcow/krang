#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);

use Krang::ClassLoader 'CGI::Contrib';
my $app = pkg('CGI::Contrib')->new(
    PARAMS => {
        RUNMODE_PERMISSIONS => {
            add            => [ 'admin_contribs' ],
            save_add       => [ 'admin_contribs' ],
            save_stay_add  => [ 'admin_contribs' ],
            save_edit      => [ 'admin_contribs' ],
            save_stay_edit => [ 'admin_contribs' ],
            delete         => [ 'admin_contribs' ]
        }
    }
)->run();
