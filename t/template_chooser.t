# test the template chooser widget

use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(InstanceElementSet);
use Krang::ClassLoader 'ElementLibrary';
use CGI;

BEGIN{ use_ok('Krang::Widget', 'template_chooser') }

# clean up when finished
my $old_instance = pkg('Conf')->instance;
END { pkg('Conf')->instance($old_instance) }

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

# set up the template chooser
my $chooser = template_chooser(name => 'name', query => CGI->new);

# check if the chooser offers all elements
for my $element (pkg('ElementLibrary')->element_names) {
    like($chooser, qr/$element/, "templae_chooser offers element '$element'");
}
