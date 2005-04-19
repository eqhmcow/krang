use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Test::More qw(no_plan);
use Krang::ClassLoader 'AddOn';
use Krang::ClassLoader Conf => qw(KrangRoot);
use File::Spec::Functions qw(catfile);
use Krang::ClassLoader 'ElementLibrary';
use Krang::ClassLoader 'Test::Apache';
use Krang::ClassLoader 'HTMLTemplate';
use Krang::ClassLoader DB => 'dbh';

# make sure Turbo isn't installed
my ($turbo) = pkg('AddOn')->find(name => 'Turbo');
ok(not $turbo);

# install Turbo 1.00
pkg('AddOn')->install(src => 
                      catfile(KrangRoot, 't', 'addons', 'Turbo-1.00.tar.gz'));

# worked?
($turbo) = pkg('AddOn')->find(name => 'Turbo');
END { $turbo->uninstall }
isa_ok($turbo, 'Krang::AddOn');
cmp_ok($turbo->version, '==', 1);
ok(-d 'addons/Turbo');
ok(-e 'addons/Turbo/lib/Krang/Turbo.pm');
ok(not -e 'lib/Krang/Turbo.pm');
ok(-e 'addons/Turbo/t/turbo.t');
ok(-e 'addons/Turbo/docs/turbo.pod');
ok(not -e 'krang_addon.conf');

# try to load Krang::Turbo
use_ok(pkg('Turbo'));

# upgrade to Turbo 1.01
pkg('AddOn')->install(src => 
                      catfile(KrangRoot, 't', 'addons', 'Turbo-1.01.tar.gz'));

# worked?
($turbo) = pkg('AddOn')->find(name => 'Turbo');
isa_ok($turbo, 'Krang::AddOn');
cmp_ok($turbo->version, '==', 1.01);
ok(-e 'addons/Turbo/lib/Krang/Turbo.pm');
ok(-e 'addons/Turbo/t/turbo.t');
ok(-e 'addons/Turbo/docs/turbo.pod');
ok(-e 'turbo_1.01_was_here');
unlink('turbo_1.01_was_here');

# install an addon with an element set
pkg('AddOn')->install(src => 
            catfile(KrangRoot, 't', 'addons', 'NewDefault-1.00.tar.gz'));
# worked?
my ($def) = pkg('AddOn')->find(name => 'NewDefault');
END { $def->uninstall }
isa_ok($def, 'Krang::AddOn');
cmp_ok($def->version, '==', 1.00);
is($def->name, 'NewDefault');

# try loading the element lib
eval { pkg('ElementLibrary')->load_set(set => "Default2") };
ok(not $@);
die $@ if $@;

# install an addon which has a src/ module
pkg('AddOn')->install(src => 
            catfile(KrangRoot, 't', 'addons', 'Clean-1.00.tar.gz'));
# worked?
my ($clean) = pkg('AddOn')->find(name => 'Clean');
END { $clean->uninstall }

# try loading HTML::Clean
eval "no warnings 'deprecated'; use HTML::Clean";
ok(not $@);
die $@ if $@;

# look for the cleaned table
my $dbh = dbh();
ok($dbh->selectrow_array("SHOW TABLES LIKE 'cleaned'"));

# install an addon with an htdocs/ script
pkg('AddOn')->install(src => 
            catfile(KrangRoot, 't', 'addons', 'LogViewer-1.00.tar.gz'));
# worked?
my ($log) = pkg('AddOn')->find(name => 'LogViewer');
END { $log->uninstall }
isa_ok($log, 'Krang::AddOn');
cmp_ok($log->version, '==', 1.00);
is($log->name, 'LogViewer');

# try loading the about.tmpl template
my $template = pkg('HTMLTemplate')->new(filename => 'about.tmpl',
                                        path     => 'About/');
like($template->output, qr/enhanced with LogViewer/);

SKIP: {
    skip "Apache server isn't up, skipping live tests", 7
      unless -e catfile(KrangRoot, 'tmp', 'httpd.pid');

    # try restarting the server, skipping if that doesn't work
    local $ENV{CGI_MODE} = 1;
    system(KrangRoot . "/bin/krang_ctl restart > /dev/null 2>&1")
      and skip "Krang servers couldn't be restarted, skipping tests.", 7;
    
    # get creds
    my $username = $ENV{KRANG_USERNAME} ? $ENV{KRANG_USERNAME} : 'admin';
    my $password = $ENV{KRANG_PASSWORD} ? $ENV{KRANG_PASSWORD} : 'whale';
    login_ok($username, $password);

    # hit about.pl and see if the server is in CGI mode, skip if not
    # since the addon won't be registered
    request_ok('about.pl', {});
    my $res = get_response();
    skip "Apache server isn't running in CGI mode, skipping live tests", 5
      unless $res->content =~ /running\s+in\s+CGI\s+mode/i;

    # hit workspace.pl and look for the new nav entries
    request_ok('workspace.pl', {});
    response_like(qr/Log Tools/);
    response_like(qr/<a.*?log_viewer.pl.*>.*?View Log/);

    # Clean should be removing spaces
    response_like(qr/<html><head><title>/);

    # try the script
    request_ok('log_viewer.pl', {});
    response_like(qr/hi mom/i);
}


# install addons which use Priority, make sure it works
pkg('AddOn')->install(src => 
            catfile(KrangRoot, 't', 'addons', 'Last-1.00.tar.gz'));
my ($last) = pkg('AddOn')->find(name => 'Last');
END { $last->uninstall }

pkg('AddOn')->install(src => 
            catfile(KrangRoot, 't', 'addons', 'AAMiddle-1.00.tar.gz'));
my ($middle) = pkg('AddOn')->find(name => 'AAMiddle');
END { $middle->uninstall }

pkg('AddOn')->install(src => 
            catfile(KrangRoot, 't', 'addons', 'First-1.00.tar.gz'));
my ($first) = pkg('AddOn')->find(name => 'First');
END { $first->uninstall }

# pull addons, looking for just these
my @addons = grep { $_->name eq 'First' or 
                    $_->name eq 'Last' or 
                    $_->name eq 'AAMiddle' } Krang::AddOn->find();
is($addons[0]->name, 'First', 'first is first');
is($addons[1]->name, 'AAMiddle', 'middle is middle');
is($addons[2]->name, 'Last', 'last is last');
