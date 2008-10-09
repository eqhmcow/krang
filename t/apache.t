use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(KrangRoot HostName ApachePort);
use Krang::ClassLoader DB   => qw(dbh);
use LWP::UserAgent;
use HTTP::Request::Common;
use File::Spec::Functions qw(catfile);
use HTTP::Cookies;

# skip tests unless Apache running
BEGIN {
    unless (-e catfile(KrangRoot, 'tmp', 'httpd.pid')) {
        eval "use Test::More skip_all => 'Krang Apache server not running.';";
    } else {
        eval "use Test::More qw(no_plan);";
    }
    die $@ if $@;
}
use Krang::ClassLoader 'Test::Web';

my $mech = pkg('Test::Web')->new();

foreach my $instance (pkg('Conf')->instances()) {
    pkg('Conf')->instance($instance);

    # try logging in with a bad password
    $mech->login_not_ok(rand(), rand());

    # try logging in with good (default) creds
    $mech->login_ok('', '', "Login INSTANCE '$instance'");

    # remove any rate_limit_hits that resulted from our bad logins
    # so the db is clean
    dbh()->do('DELETE FROM rate_limit_hits');
}

