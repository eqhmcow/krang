use Test::More qw(no_plan);
use strict;
use warnings;

use Krang;
use Krang::Conf qw(ElementSet);
BEGIN { use_ok('Krang::ElementLibrary') }

# try to load the element set for each instance
my $old_instance = Krang::Conf->instance();
foreach my $instance (Krang::Conf->instances()) {
    Krang::Conf->instance($instance);
    ok(Krang::ElementLibrary->load_set(set => ElementSet));

    # recurse through classes, giving them a checkup
    my @top = Krang::ElementLibrary->top_levels();
    ok(@top, "top_levels exist " . ElementSet);
    foreach my $name (@top) {
        my $class = Krang::ElementLibrary->top_level(name => $name);
        check_kids($class);
    }
}
Krang::Conf->instance($old_instance);

sub check_kids {
    my $class = shift;
    isa_ok($class, "Krang::ElementClass");
    ok($class->name, $class->name . " found");
    for ($class->children()) {
        is($class->child($_->name), $_, $class->name . "->child(" . $_->name . ") == " . $_->name . ")");
        check_kids($_);
    }
}

