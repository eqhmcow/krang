#!/usr/bin/perl -w
use CGI;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'CGI::Bugzilla';

# create a new CGI object that uses the QUERY_STRING environment
# variable so it doesn't get pick up the redirect's parameters.
# but we do need to pass window_id along, so get that from the
# original
my $redirect_cgi = CGI->new();
my $cgi = CGI->new($ENV{QUERY_STRING});
$cgi->param(window_id => $redirect_cgi->param('window_id'));

pkg('CGI::Bugzilla')->new(QUERY => $cgi)->run();
