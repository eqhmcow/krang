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
    $dbh->do('ALTER table story add column last_modified_date datetime not null');
    $dbh->do('ALTER table media add column last_modified_date datetime not null');
}

sub per_installation {
    # nothing yet
}

1;
