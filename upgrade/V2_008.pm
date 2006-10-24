package V2_008;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
use Krang::ClassLoader Conf => 'KrangRoot';
use File::Spec::Functions qw(catfile);
 
# nothing yet
sub per_instance {
    my $self = shift;

    my $dbh  = dbh();

    print "Adding rate_limit_hits table and scheduling cleanup task\n";
    eval {
        $dbh->do(q(
            CREATE TABLE rate_limit_hits (
               user_id   VARCHAR(255)      NOT NULL,
               action    VARCHAR(255)      NOT NULL,
               timestamp INTEGER UNSIGNED NOT NULL,
               INDEX (user_id, action),
               INDEX (user_id, action, timestamp)
            ) TYPE=MyISAM;
        ));
    };
    
    eval {
        $dbh->do(q(
            INSERT INTO schedule
             (`repeat`, action, object_type, initial_date, last_run, next_run, hour, minute)
            VALUES
             ('daily', 'clean', 'rate_limit', NOW(), NOW(), NOW(), 3, 0);
        ));
    }
    warn("Failed to schedule rate_limit cleanup: $@") if( $@ );
}

# add new krang.conf directive, Charset
sub per_installation {}

1;
