package V0_014;
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

    $dbh->do("ALTER TABLE contrib ADD COLUMN media_id mediumint unsigned default NULL");

}


1;
