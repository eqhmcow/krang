use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(KrangRoot HostName ApachePort);
use LWP::UserAgent;
use HTTP::Request::Common;
use File::Spec::Functions qw(catfile);
use HTTP::Cookies;

# skip tests unless Apache running
BEGIN {
    unless (-e catfile(KrangRoot, 'tmp', 'httpd.pid')) {
        eval "use Test::More skip_all => 'Krang Apache server not running.';";
    } else {
        eval "use Test::More qw(no_plan);"
    }
    die $@ if $@;
}
use Krang::ClassLoader 'Test::Apache';

# get creds
my $username = $ENV{KRANG_USERNAME} ? $ENV{KRANG_USERNAME} : 'admin';
my $password = $ENV{KRANG_PASSWORD} ? $ENV{KRANG_PASSWORD} : 'whale';

foreach my $instance (pkg('Conf')->instances()) {
    pkg('Conf')->instance($instance);

    # try logging in with a bad password
    login_not_ok(rand(), rand());
    
    # try logging in with good creds
    login_ok($username, $password, "Login INSTANCE '$instance' with 'KRANG_USERNAME=$username' and 'KRANG_PASSWORD=$password'");
}
