package V1_021;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);

sub per_instance {
    my $self = shift;
    my $dbh  = dbh();

    # add missing indexes to list tables.  If these fail that's most
    # likely because they already exist, so just warn on error.
    eval {
        $dbh->do("ALTER TABLE list ADD INDEX (list_group_id)");
        $dbh->do("ALTER TABLE list_item ADD INDEX (list_id)");
        $dbh->do("ALTER TABLE list_item ADD INDEX (parent_list_item_id)");
        $dbh->do("ALTER TABLE list_item ADD INDEX (ord)");
        $dbh->do("ALTER TABLE list_item ADD INDEX (data)");
    };
    warn("Attempt to add some list indexes failed: $@")
      if $@;
}

# nothing yet
sub per_installation {}

1;
