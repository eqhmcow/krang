package V1_025;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);
use Krang::User;
use Krang::Group;

#
# changes in 1.025:
#
# Fix a bug in 1.024 - all NULL values for the column 'hidden' should be zero.
#

sub per_instance {
    my $self = shift;

    my $dbh  = dbh();

    eval {
        $dbh->do("UPDATE story SET hidden=0 where hidden is NULL");
    };

    if ($@) {
        warn("Attempt to set story.hidden=0 where story.hidden is NULL failed: $@");
    }

}

# nothing yet
sub per_installation {}

1;

