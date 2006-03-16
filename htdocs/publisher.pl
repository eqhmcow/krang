#!/usr/bin/perl -w
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'CGI::Publisher';
my $app = pkg('CGI::Publisher')->new(
    PARAMS => {
        RUNMODE_PERMISSIONS => {
            publish_story       => [qw(may_publish)],
            publish_story_list  => [qw(may_publish)],
            publish_assets      => [qw(may_publish)],
            publish_media       => [qw(may_publish)],
        },
    },
)->run();
