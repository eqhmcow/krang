#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Template';
my $app = pkg('CGI::Template')->new(
    PARAMS => {
        PACKAGE_ASSETS => { template => [qw(read-only edit)] },
        RUNMODE_ASSETS => {
            add               => { template => ['edit'] },
            add_cancel        => { template => ['edit'] },
            add_save          => { template => ['edit'] },
            add_checkin       => { template => ['edit'] },
            add_save_stay     => { template => ['edit'] },
            cancel_add        => { template => ['edit'] },
            cancel_edit       => { template => ['edit'] },
            checkin_selected  => { template => ['edit'] },
            delete            => { template => ['edit'] },
            delete_selected   => { template => ['edit'] },
            deploy            => { template => ['edit'] },
            deploy_selected   => { template => ['edit'] },
            checkout_and_edit => { template => ['edit'] },
            edit              => { template => ['edit'] },
            edit_cancel       => { template => ['edit'] },
            edit_save         => { template => ['edit'] },
            edit_checkin      => { template => ['edit'] },
            edit_save_stay    => { template => ['edit'] },
            revert_version    => { template => ['edit'] },
            save_and_view_log => { template => ['edit'] },
          },
    },
)->run;
