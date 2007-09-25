# test the template chooser widget

use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(InstanceElementSet);
use Krang::ClassLoader 'ElementLibrary';
use CGI;

BEGIN{ use_ok('Krang::Widget', qw(template_chooser_object)) }

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
my $query = CGI->new();
my $chooser = template_chooser_object(name => 'name', query => $query);
my $content = $chooser->handle_get_node( query => $query );
my @top_levels = pkg('ElementLibrary')->top_levels;

# make sure all the top level elements are there
foreach my $element (@top_levels) {
    like($content, qr/\Q$element\E/, "template_choose offers top-level '$element'");
}

# now make sure the children of each top level is there too
for(my $i = 0; $i<@top_levels; $i++) {
    # get the node contents for this element
    my $el = pkg('ElementLibrary')->top_level(name => $top_levels[$i]);
    $query->param(id => $i);
    $content = $chooser->handle_get_node(query => $query);

    # now check each child
    my @children = $el->children();
    foreach my $child ($el->children) {
        my $name = ref $child ? $child->name : $child;
        like($content, qr/\Q$name\E/, "template_chooser offers child element '$name'");
    }
}
