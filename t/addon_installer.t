use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Test::More qw(no_plan);
use Krang::ClassLoader DB => 'dbh';
use Krang::ClassLoader 'AddOn';
use Krang::ClassLoader Conf => qw(KrangRoot);
use File::Spec::Functions qw(catfile catdir);
use Krang::ClassLoader 'ElementLibrary';
use Krang::ClassLoader 'Test::Web';
use Krang::ClassLoader 'Test::Util' => qw(restart_krang);
use Krang::ClassLoader 'HTMLTemplate';
use IPC::Run qw(run);

# make sure Turbo isn't installed
my ($turbo) = pkg('AddOn')->find(name => 'Turbo');
ok(!$turbo, "Addon 'Turbo' does not exist");

# install Turbo 1.00
pkg('AddOn')->install(src => catfile(KrangRoot, 't', 'addons', 'Turbo-1.00.tar.gz'));

# worked?
($turbo) = pkg('AddOn')->find(name => 'Turbo');
END { $turbo->uninstall }
isa_ok($turbo, 'Krang::AddOn');
cmp_ok($turbo->version, '==', 1, 'Version 1.00');

my $addon_dir = catdir(KrangRoot, 'addons', 'Turbo');
ok(-d $addon_dir, "'$addon_dir' exists");

for my $addon_file (
    catfile(KrangRoot, 'addons', 'Turbo', 'lib',  'Krang', 'Turbo.pm'),
    catfile(KrangRoot, 'addons', 'Turbo', 't',    'turbo.t'),
    catfile(KrangRoot, 'addons', 'Turbo', 'docs', 'turbo.pod'),
    catfile(KrangRoot, 'addons', 'Turbo', 'krang_addon.conf'),
  )
{
    ok(-e $addon_file, "'$addon_file' exists");
}

for
  my $file (catfile(KrangRoot, 'lib', 'Krang', 'Turbo.pm'), catfile(KrangRoot, 'krang_addon.conf'),)
{
    ok(!-e $file, "'$file' does not exist");
}

# try to load Krang::Turbo
use_ok(pkg('Turbo'));

# upgrade to Turbo 1.01
pkg('AddOn')->install(src => catfile(KrangRoot, 't', 'addons', 'Turbo-1.01.tar.gz'));

# worked?
($turbo) = pkg('AddOn')->find(name => 'Turbo');
isa_ok($turbo, 'Krang::AddOn');
cmp_ok($turbo->version, '==', 1.01, "Version 1.01");

for my $addon_file (
    catfile(KrangRoot, 'addons', 'Turbo', 'lib',  'Krang', 'Turbo.pm'),
    catfile(KrangRoot, 'addons', 'Turbo', 't',    'turbo.t'),
    catfile(KrangRoot, 'addons', 'Turbo', 'docs', 'turbo.pod'),
    catfile(KrangRoot, 'addons', 'Turbo', 'krang_addon.conf'),
    catfile(KrangRoot, 'turbo_1.01_was_here'),
  )
{
    ok(-e $addon_file, "'$addon_file' exists");
}

unlink(catfile(KrangRoot, 'turbo_1.01_was_here'));

# install an addon with an element set
pkg('AddOn')->install(src => catfile(KrangRoot, 't', 'addons', 'NewDefault-1.00.tar.gz'));

# worked?
my ($def) = pkg('AddOn')->find(name => 'NewDefault');
END { $def->uninstall }
isa_ok($def, 'Krang::AddOn');
cmp_ok($def->version, '==', 1.00, "Version 1.00");
is($def->name, 'NewDefault', "Addon name: NewDefault");

# try loading the element lib
eval { pkg('ElementLibrary')->load_set(set => "Default2") };
ok(!$@, "Load elementset 'Default2'");
die $@ if $@;

# install an addon which has a src/ module
pkg('AddOn')->install(src => catfile(KrangRoot, 't', 'addons', 'Clean-1.00.tar.gz'));

# worked?
my ($clean) = pkg('AddOn')->find(name => 'Clean');
END { $clean->uninstall }

# try loading HTML::Clean
eval "no warnings 'deprecated'; use HTML::Clean";
ok(!$@, "Loading 'HTML::Clean'");
die $@ if $@;

# look for the cleaned table
my $dbh = dbh();
ok($dbh->selectrow_array("SHOW TABLES LIKE 'cleaned'"), "DB table 'cleaned' exists");

# try and export/import cycle - Clean implements a new data-set class
{
    my $krang_export = catfile(KrangRoot, 'bin', 'krang_export');
    my $krang_import = catfile(KrangRoot, 'bin', 'krang_import');
    my $kds          = catfile(KrangRoot, 'tmp', 'export.kds');
    my ($in, $out, $err) = ("", "", "");
    my @export_cmd = ($krang_export, '--overwrite', '--verbose', '--output', $kds, '--everything');
    my @import_cmd = ($krang_import, '--verbose', $kds);

    run(\@export_cmd, \$in, \$out, \$err);
    like($out, qr/Export completed/, 'export worked');
    ok(-s $kds);

    # look for the Clean::Record objects
    like($err, qr/Adding record 1/, 'Clean::Record 1 exported');
    like($err, qr/Adding record 2/, 'Clean::Record 2 exported');
    like($err, qr/Adding record 2/, 'Clean::Record 3 exported');

    # try importing
    run(\@import_cmd, \$in, \$out, \$err);
    like($out, qr/Import completed/, 'import worked');
    ok(-s $kds);

    # look for the Clean::Record objects
    like($err, qr/Clean::Record => 1/, 'Clean::Record 1 imported');
    like($err, qr/Clean::Record => 2/, 'Clean::Record 2 imported');
    like($err, qr/Clean::Record => 3/, 'Clean::Record 3 imported');

    unlink $kds;
}

# install an addon with an htdocs/ script
pkg('AddOn')->install(src => catfile(KrangRoot, 't', 'addons', 'LogViewer-1.00.tar.gz'));

# worked?
my ($log) = pkg('AddOn')->find(name => 'LogViewer');
END { $log->uninstall }
isa_ok($log, 'Krang::AddOn');
cmp_ok($log->version, '==', 1.00, "Version 1.00");
is($log->name, 'LogViewer', "Addon name: 'LogViewer'");

# try loading the about.tmpl template
my $template = pkg('HTMLTemplate')->new(
    filename => 'about.tmpl',
    path     => 'About/'
);
like($template->output, qr/enhanced with LogViewer/, "Loading template");

pkg('AddOn')->install(src => catfile(KrangRoot, 't', 'addons', 'SchedulerAddon-1.00.tar.gz'));
my ($sched) = pkg('AddOn')->find(name => 'SchedulerAddon');
END { $sched->uninstall }
isa_ok($sched, 'Krang::AddOn');
cmp_ok($sched->version, '==', 1.00, "Version 1.00");
is($sched->name, 'SchedulerAddon', "Addon name: 'SchedulerAddon'");

SKIP: {
    skip "Apache server isn't up, skipping live tests", 7
      unless -e catfile(KrangRoot, 'tmp', 'httpd.pid');

    # try restarting the server, skipping if that doesn't work
    local $ENV{CGI_MODE} = 1;
    restart_krang()
      or skip "Krang servers couldn't be restarted, skipping tests.", 7;

    # get creds
    my $mech = pkg('Test::Web')->new();
    $mech->login_ok()
      or die "Unable to login!  Aborting tests.";

    # remove any rate_limit_hits that resulted from our login
    # so the db is clean
    dbh()->do('DELETE FROM rate_limit_hits');

    # hit about.pl and see if the server is in CGI mode, skip if not
    # since the addon won't be registered
    $mech->get_ok('about.pl', "Request for about.pl");
    skip "Apache server isn't running in CGI mode, skipping live tests", 5
      unless $mech->content =~ /running\s+in\s+CGI\s+mode/i;

    # hit workspace.pl and look for the new nav entries
    $mech->get_ok('workspace.pl');
    $mech->content_contains('Log Tools');
    $mech->content_like(qr/<a.*?log_viewer.pl.*>.*?View Log/);
    ## SchedulerAddon entry
    $mech->content_contains('schedule.pl?advanced_schedule=1&amp;rm=edit_admin');

    # Clean should be removing spaces
    $mech->content_like(qr/<html[^>]*><head[^>]*><title[^>]*>/);

    # try the script
    $mech->get_ok('log_viewer.pl');
    $mech->content_like(qr/hi mom/i);
}

# install addons which use Priority, make sure it works
pkg('AddOn')->install(src => catfile(KrangRoot, 't', 'addons', 'Last-1.00.tar.gz'));
my ($last) = pkg('AddOn')->find(name => 'Last');
END { $last->uninstall }

pkg('AddOn')->install(src => catfile(KrangRoot, 't', 'addons', 'AAMiddle-1.00.tar.gz'));
my ($middle) = pkg('AddOn')->find(name => 'AAMiddle');
END { $middle->uninstall }

pkg('AddOn')->install(src => catfile(KrangRoot, 't', 'addons', 'First-1.00.tar.gz'));
my ($first) = pkg('AddOn')->find(name => 'First');
END { $first->uninstall }

# pull addons, looking for just these
my @addons =
  grep { $_->name eq 'First' or $_->name eq 'Last' or $_->name eq 'AAMiddle' } pkg('AddOn')->find();
is($addons[0]->name, 'First',    'first is first');
is($addons[1]->name, 'AAMiddle', 'middle is middle');
is($addons[2]->name, 'Last',     'last is last');
