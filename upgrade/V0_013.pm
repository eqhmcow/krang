package V0_013;
use strict;
use warnings;
use base 'Krang::Upgrade';


use Krang::Conf qw(InstanceDBName DBUser DBPass KrangRoot);
use Krang::DB qw(dbh);


# Nothing to do for this version....
sub per_installation {
    my $self = shift;

    print STDERR "$self\::per_installation:  KrangRoot => '". KrangRoot ."'\n";
}


# Create db_version table
sub per_instance {
    my $self = shift;

    my $dbh = dbh();
    my $instance = Krang::Conf->instance();
    print STDERR "$self\::per_instance:  instance => '$instance' ($dbh)\n";
}


1;
