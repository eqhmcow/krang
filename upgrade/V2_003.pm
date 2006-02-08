package V2_003;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
 
#
# Upgrading from V2.002
#
 
sub per_instance {

    my $self = shift;

    $self->_modify_index_on_table_mypref();

    # other stuff
}

# nothing yet
sub per_installation {}

#
# include user_id and id in PRIMARY KEY to make sure
# users don't clobber each others preferences
#
sub _modify_index_on_table_mypref {

    my $dbh  = dbh();

    eval {
        $dbh->do("alter table my_pref drop primary key")
    };

    if ($@) {
        warn("Failed to drop primary key on table 'my_pref': $@");
    }

    eval {
	$dbh->do("alter table my_pref add primary key (user_id, id)")
    };

    if ($@) {
	warn("Failed to add primary key (user_id, id) on table my_pref: $@");
    }
}

1;
