package V2_006;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
use Krang::ClassLoader Conf => 'KrangRoot';
use File::Spec::Functions qw(catfile);
 
# nothing yet
sub per_instance {
    my $self = shift;

    my $dbh  = dbh();

    print "Adding index element_root_id_class (may take a while)...\n";
    eval {
        $dbh->do(qq{ CREATE INDEX element_root_id_class ON element (root_id, class(100)) });
    };
    if ($@) {
        warn("Failed to add index element_root_id_class: $@");
    }

}

# add new krang.conf directive, Charset
sub per_installation {}

1;
