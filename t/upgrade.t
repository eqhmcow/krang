use Krang::ClassFactory qw(pkg);
use warnings;
use strict;
use Test::More qw(no_plan);

use Krang::ClassLoader 'Script';

my $upmod_path;

BEGIN {
    # Path to uprade modules
    $upmod_path = $ENV{KRANG_ROOT} ."/upgrade";
    unshift(@INC, $upmod_path);
}

find_and_test_upgrade_modules();

sub find_and_test_upgrade_modules {
    # Find upgrade modules

    opendir(DIR, $upmod_path) || die ("Unable to open upgrade directory '$upmod_path': $!");
    my @upmodules = (grep {
        (-f "$upmod_path/$_") && (/^V(\d+)\_(\d+)\.pm$/)
    } readdir(DIR));
    closedir(DIR);

    # Test upgrade modules
    foreach my $upmod (@upmodules) {
        test_upgrade_module($upmod);
    }
}


sub test_upgrade_module {
    my $module = shift;

    # Get package name by trimming off ".pm"
    my $package = $module;
    $package =~ s/\.pm$//;

    # Can we load the module?
    require_ok($package);

    # Does it have all the required methods?
    can_ok($package, qw/new upgrade per_installation per_instance/);

    # Can we construct one?
    my $upgrade = $package->new();
    ok(ref($upgrade), "$package->new()");

    # IS it a sub-class of Krang::Upgrade?
    isa_ok($upgrade, "Krang::Upgrade");
}


