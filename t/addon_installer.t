use strict;
use warnings;

use Krang::Script;
use Test::More qw(no_plan);
use Krang::AddOn;
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

# make sure Turbo isn't installed
my ($turbo) = Krang::AddOn->find(name => 'Turbo');
ok(not $turbo);

# install Turbo 1.00
my $installer = catfile(KrangRoot, 'bin', 'krang_addon_installer');
my $cmd = $installer . " " .
  catfile(KrangRoot, 't', 'addons', 'Turbo-1.00.tar.gz');
system("$cmd > /dev/null");

# worked?
($turbo) = Krang::AddOn->find(name => 'Turbo');
isa_ok($turbo, 'Krang::AddOn');
cmp_ok($turbo->version, '==', 1);
ok(-e 'lib/Krang/Turbo.pm');
ok(-e 't/turbo.t');
ok(-e 'docs/turbo.pod');
ok(not -e 'krang_addon.conf');

# upgrade to Turbo 1.01
$cmd = $installer . " " .
  catfile(KrangRoot, 't', 'addons', 'Turbo-1.01.tar.gz');
system("$cmd > /dev/null");

# worked?
($turbo) = Krang::AddOn->find(name => 'Turbo');
isa_ok($turbo, 'Krang::AddOn');
cmp_ok($turbo->version, '==', 1.01);
ok(-e 'lib/Krang/Turbo.pm');
ok(-e 't/turbo.t');
ok(-e 'docs/turbo.pod');
ok(-e 'turbo_1.01_was_here');
ok(not -e 'krang_addon.conf');

# clean up
$turbo->delete;
unlink('lib/Krang/Turbo.pm');
unlink('t/turbo.t');
unlink('docs/turbo.pod');
unlink('turbo_1.01_was_here');
