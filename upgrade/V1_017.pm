package V1_017;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);
use Krang::Group;
use Krang::Script;

sub per_instance {
    my $self = shift;

    my $dbh  = dbh();


    ########################################
    # Krang::Story and Krang::Media changes

    # the story and media tables each have a new column, preview_version.
    # add the new column to the table, there is no need to set a value at this time.
    $dbh->do("ALTER TABLE story ADD COLUMN preview_version INT UNSIGNED");
    $dbh->do("ALTER TABLE media ADD COLUMN preview_version INT UNSIGNED");

    print "Rebuilding permissions cache...\n";
    Krang::Group->rebuild_category_cache();
}

# nothing yet
sub per_installation {}

1;

