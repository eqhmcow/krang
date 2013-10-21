package V3_24;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'Media';

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();
    $dbh->do('ALTER TABLE history
    ADD COLUMN `schedule_id` INT(10) UNSIGNED DEFAULT NULL after `user_id`
    ');

}

sub per_installation {
    my ($self, %args) = @_;

    # nothing to do yet
}

1;
