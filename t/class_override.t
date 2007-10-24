use strict;
use warnings;

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'AddOn';
use Krang::ClassLoader Conf => qw(KrangRoot);
use Krang::ClassLoader 'Test::Web';
use Krang::ClassLoader 'Test::Util' => qw(restart_krang);
use File::Spec::Functions qw(catfile catdir);

use Test::More qw(no_plan);

# basic functionality
is(pkg('Story'), 'Krang::Story');
is(pkg('CGI::Story'), 'Krang::CGI::Story');
is(pkg('Bogus'), 'Krang::Bogus');

# load an addon with a class override for Krang::CGI::About
pkg('AddOn')->install(src => catfile(KrangRoot, 't', 'addons', 'AboutPlus-1.00.tar.gz'));

# worked?
my ($aboutp) = pkg('AddOn')->find(name => 'AboutPlus');
END { $aboutp->uninstall }

# did the override take?
is(pkg('CGI::About'), 'AboutPlus::About');

# do a live web test
SKIP: {
    skip "Apache server isn't up, skipping live tests", 7
      unless -e catfile(KrangRoot, 'tmp', 'httpd.pid');

    # try restarting the server, skipping if that doesn't work
    local $ENV{CGI_MODE} = 1;

    restart_krang() or
        skip "Krang servers couldn't be restarted, skipping tests.", 7;

    # get creds
    my $mech = pkg('Test::Web')->new();
    $mech->login_ok();

    # hit about.pl and see if the server is in CGI mode, skip if not
    # since the addon won't be registered
    $mech->get_ok('about.pl');
    skip "Apache server isn't running in CGI mode, skipping live tests", 5
      unless $mech->content =~ /running\s+in\s+CGI\s+mode/i;

    $mech->content_like(qr/PLUS BIG IMPROVEMENTS/);

    # hit the barf runmode which tests messages.conf extensions
    $mech->get_ok('about.pl?rm=barf');
    $mech->content_like(qr/Barf!/);
    $mech->content_like(qr/Barf\s+Barf/);
}
