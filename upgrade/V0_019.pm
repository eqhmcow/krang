package V0_019;
use strict;
use warnings;
use base 'Krang::Upgrade';


use Krang::Conf qw(InstanceDBName DBUser DBPass KrangRoot);
use Krang::DB qw(dbh);


# Nothing to do for this version....
sub per_installation {
    my $self = shift;
}


# add media_id column to the contrib table
sub per_instance {
    my $self = shift;

    my $dbh = dbh();
    my $instance = Krang::Conf->instance();

    # drop the unique index and add a non-unique one
    $dbh->do("ALTER TABLE element_index DROP INDEX element_id");
    $dbh->do("ALTER TABLE element_index ADD INDEX (element_id)");
}


1;
