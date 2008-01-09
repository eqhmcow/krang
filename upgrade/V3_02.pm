package V3_02;
use strict;
use warnings;

use Krang::ClassLoader base => 'Upgrade';

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader Conf => qw(KrangRoot);
use Krang::ClassLoader DB => qw(dbh);

sub per_installation {
    _update_config();
}


sub per_instance {
    my $self = shift;
    my $dbh = dbh();

    # add the 'language' preference
    $dbh->do('INSERT INTO pref (id, value) VALUES ("language", "en")');
}

1;
