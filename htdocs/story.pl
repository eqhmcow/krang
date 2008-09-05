#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Story';
pkg('CGI::Story')->new(
    PARAMS => {
        PACKAGE_ASSETS => { story => [qw(read-only edit)] },
        RUNMODE_ASSETS => {
            new_story                     => { story => ['edit'] },
            create                        => { story => ['edit'] },
            edit                          => { story => ['edit'] },
            checkout_and_edit             => { story => ['edit'] },
            check_in                      => { story => ['edit'] },
            revert                        => { story => ['edit'] },
            delete                        => { story => ['edit'] },
            delete_selected               => { story => ['edit'] },
            checkout_selected             => { story => ['edit'] },
            checkin_selected              => { story => ['edit'] },
            delete_categories             => { story => ['edit'] },
            add_category                  => { story => ['edit'] },
            set_primary_category          => { story => ['edit'] },
            copy                          => { story => ['edit'] },
            db_save                       => { story => ['edit'] },
            db_save_and_stay              => { story => ['edit'] },
            save_and_jump                 => { story => ['edit'] },
            save_and_add                  => { story => ['edit'] },
            save_and_publish              => { story => ['edit'] },
            save_and_view                 => { story => ['edit'] },
            save_and_view_log             => { story => ['edit'] },
            save_and_stay                 => { story => ['edit'] },
            save_and_edit_contribs        => { story => ['edit'] },
            save_and_edit_schedule        => { story => ['edit'] },
            save_and_go_up                => { story => ['edit'] },
            save_and_bulk_edit            => { story => ['edit'] },
            save_and_leave_bulk_edit      => { story => ['edit'] },
            save_and_change_bulk_edit_sep => { story => ['edit'] },
            save_and_find_story_link      => { story => ['edit'] },
            save_and_find_media_link      => { story => ['edit'] },
            archive                       => { story => ['edit'] },
            unarchive                     => { story => ['edit'] },
        },
    },
)->run();
