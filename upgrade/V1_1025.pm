package V1_1025;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);
use Krang::User;
use Krang::Group;

#
# changes in 1.1025:
#
# Added new permission, "admin_categories_ftp" to permit (or not) users to 
# create/modify/delete categories via FTP.
#

sub per_instance {
    my $self = shift;

    my $dbh  = dbh();

    eval {
        $dbh->do("alter table group_permission ADD COLUMN admin_categories_ftp BOOL NOT NULL DEFAULT 0");
    };

    if ($@) {
        warn("Failed to alter table group_permission: $@");
    }

}

# nothing yet
sub per_installation {}

1;

