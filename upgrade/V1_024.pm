package V1_024;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);
use Krang::User;
use Krang::Group;

#
# changes in 1.024:
#
# A new column 'hidden' has been added to the story table.
#

sub per_instance {
    my $self = shift;

    my $dbh  = dbh();

    # add the new hidden column to 'story' unless it already exists
    my @rows = $dbh->selectrow_array("SHOW COLUMNS FROM story LIKE 'hidden'");
    unless (@rows) {
        eval {
            $dbh->do("ALTER TABLE story ADD COLUMN hidden BOOL");
            $dbh->do("ALTER TABLE story ALTER COLUMN hidden SET DEFAULT 0");
        };
        warn("Attempt to add column 'hidden' to story table failed: $@")
          if $@;
    }

}

# nothing yet
sub per_installation {}

1;

