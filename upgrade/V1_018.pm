package V1_018;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);
use Krang::User;

sub per_instance {
    my $self = shift;

    my $dbh  = dbh();

    # add the new hidden column to 'user'
    $dbh->do("ALTER TABLE user ADD COLUMN hidden BOOL");
    $dbh->do("ALTER TABLE user ALTER COLUMN hidden SET DEFAULT 0");

    # add 'system' user
    Krang::User->new(login      => 'system',
                     email      => 'system@noemail.com',
                     first_name => 'System',
                     last_name  => 'User',
                     password   => '*',
                     encrypted  => 1,
                     hidden     => 1,
                    )->save();
}

# nothing yet
sub per_installation {}

1;

