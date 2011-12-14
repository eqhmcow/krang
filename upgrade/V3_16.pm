package V3_16;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB   => 'dbh';

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();
    $dbh->do('ALTER table schedule ENGINE=InnoDB');
    $dbh->do('ALTER table schedule add column daemon_uuid varchar(128) default null');
}

sub per_installation {
    my ($self, %args) = @_;
    # remove old files
    $self->remove_files(
        qw(
          src/Module-Build-0.30.tar.gz
          src/Params-Validate-0.88.tar.gz
          )
    );

}

1;
