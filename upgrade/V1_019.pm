package V1_019;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);

sub per_instance {
    my $self = shift;

    my $dbh  = dbh();

    # fix NULL values for hidden to be 0
    $dbh->do('UPDATE user SET hidden = 0 WHERE hidden IS NULL');
}

sub per_installation {}

1;

