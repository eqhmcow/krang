package V0_012;


use Krang::Conf qw(InstanceDBName DBUser DBPass KrangRoot);
use Krang::DB qw(dbh);


# Nothing to do for this version....
sub per_installation {
    my $pkg = shift;

    print STDERR "$pkg::per_installation:  KrangRoot => '". KrangRoot ."'\n";
}


# Create db_version table
sub per_instance {
    my $pkg = shift;

    my $dbh = dbh();
    my $instance = Krang::Conf->instance();
    print STDERR "$pkg::per_instance:  instance => '$instance' ($dbh)\n";
}


1;
