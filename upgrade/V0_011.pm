package V0_011;
use strict;
use warnings;
use base 'Krang::Upgrade';


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

    print "Creating db_version table";
    my $create_sql = <<EOSQL;
CREATE TABLE db_version (
        db_version VARCHAR(255) NOT NULL
)
EOSQL
    $dbh->do($create_sql);

    # Insert base data
    $dbh->do("INSERT INTO db_version (db_version) VALUES ('0')");

    # Add mime_type column to media table
    $dbh->do("ALTER TABLE media ADD COLUMN mime_type varchar(255)");
}


1;
