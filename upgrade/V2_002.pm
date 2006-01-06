package V2_002;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);
use Krang::User;
use Krang::Group;

#
# changes in 2.002:
#
# Added new permission, "admin_scheduler" to permit (or not) users to 
# access addon related admin scheduler screen
#

sub per_instance {
    my $self = shift;

    my $dbh  = dbh();

    eval {
        $dbh->do("alter table group_permission ADD COLUMN admin_scheduler tinyint(1) NOT NULL DEFAULT 0");
    };

    if ($@) {
        warn("Failed to alter table group_permission: $@");
    }

    eval {
        $dbh->do("update group_permission set admin_scheduler = 1 where group_id = 1");
    };

    if ($@) {
        warn("Failed to set grant default permission from admin_scheduler for admin_group: $@");
    }
}

# nothing yet
sub per_installation {}

1;

