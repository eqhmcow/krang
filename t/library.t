use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(InstanceElementSet);
BEGIN { use_ok(pkg('ElementLibrary')) }

# try to load the element set for each instance
my $old_instance = pkg('Conf')->instance();
foreach my $instance (pkg('Conf')->instances()) {
    pkg('Conf')->instance($instance);
    ok(pkg('ElementLibrary')->load_set(set => InstanceElementSet), "load_set()");

    # check that element_names works
    my @names = pkg('ElementLibrary')->element_names();
    ok(@names, "element_names returned something");

    # recurse through classes, giving them a checkup
    my @top = pkg('ElementLibrary')->top_levels();
    ok(@top, "top_levels exist " . InstanceElementSet);
    foreach my $name (@top) {
        ok((grep { $_ eq $name } @names), "$name is in element_names");
        my $class = pkg('ElementLibrary')->top_level(name => $name);
        check_kids($class);
    }

}
pkg('Conf')->instance($old_instance);

sub check_kids {
    my $class = shift;
    isa_ok($class, "Krang::ElementClass");
    ok($class->name, $class->name . " found");
    for ($class->children()) {
        is($class->child($_->name), $_, scalar($class->name . "->child(" . $_->name . ") == " . $_->name . ")") );
        check_kids($_);
    }
}

