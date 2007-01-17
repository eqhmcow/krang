#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Media';
pkg('CGI::Media')->new(
    PARAMS => {
        PACKAGE_ASSETS => { media => [qw(read-only edit)] },
        RUNMODE_ASSETS => {
            add                      => { media => ['edit'] },
            save_add                 => { media => ['edit'] },
            cancel_add               => { media => ['edit'] },
            checkin_add              => { media => ['edit'] },
            checkin_edit             => { media => ['edit'] },
            checkin_selected         => { media => ['edit'] },
            save_stay_add            => { media => ['edit'] },
            checkout_and_edit        => { media => ['edit'] },
            checkout_selected        => { media => ['edit'] },
            edit                     => { media => ['edit'] },
            save_edit                => { media => ['edit'] },
            save_stay_edit           => { media => ['edit'] },
            delete                   => { media => ['edit'] },
            delete_selected          => { media => ['edit'] },
            save_and_associate_media => { media => ['edit'] },
            save_and_view_log        => { media => ['edit'] },
            save_and_publish         => { media => ['edit'] },
            save_and_preview         => { media => ['edit'] },
            revert_version           => { media => ['edit'] },
            save_and_edit_schedule   => { media => ['edit'] },
        },
    },
)->run();
