package V1_015;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::DB qw(dbh);
use Krang::Schedule;

sub per_installation { }

sub per_instance {
    my $self = shift;
    my $dbh = dbh();

    # Krang was missing setup SQL for the default scheduled tasks, add
    # them now
    foreach my $which (qw(tmp session analyze)) {
        unless (Krang::Schedule->find(object_type => $which, count => 1)) {
            Krang::Schedule->new(action      => 'clean',
                                 object_type => $which,
                                 repeat      => 'daily',
                                 hour        => 3,
                                 minute      => 0,
                                )->save();
        }
    }
}

1;
