package V1_018;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);
use Krang::User;
use Krang::Group;

sub per_instance {
    my $self = shift;

    my $dbh  = dbh();

    # add the new hidden column to 'user' unless it already exists
    my @rows = $dbh->selectrow_array("SHOW COLUMNS FROM user LIKE 'hidden'");
    unless (@rows) {
        $dbh->do("ALTER TABLE user ADD COLUMN hidden BOOL");
        $dbh->do("ALTER TABLE user ALTER COLUMN hidden SET DEFAULT 0");
    }

    # add 'system' user if one does not exists
    unless (Krang::User->find(login => 'system', count => 1)) {
        my ($group_id) = Krang::Group->find(name => 'Admin', ids_only => 1);
        my $user = Krang::User->new(login      => 'system',
                                    email      => 'system@noemail.com',
                                    first_name => 'System',
                                    last_name  => 'User',
                                    password   => '*',
                                    encrypted  => 1,
                                    hidden     => 1,
                                   );
        $user->group_ids($group_id);
        $user->save();
    }

    # rebuild permissions cache, moved here from V1_017 because it
    # will fail with the current Krang::User before user.hidden is
    # added
    print "Rebuilding permissions cache...\n";

    # setup REMOTE_USER, needed by Krang::Group
    local $ENV{REMOTE_USER} = (Krang::User->find(login => 'system', 
                                                 ids_only => 1))[0];
    Krang::Group->rebuild_category_cache();
}

# nothing yet
sub per_installation {}

1;

