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

    # add new tables and data for login security
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
    };
    warn("Failed to schedule rate_limit cleanup: $@") if( $@ );
    eval {
        $dbh->do(q(
            CREATE TABLE old_password (
                    user_id     INT UNSIGNED NOT NULL,
                    password    VARCHAR(255) NOT NULL,
                    timestamp   INT UNSIGNED,
                    KEY (user_id),
                    PRIMARY KEY (user_id, password)
            );
        ));
    };
    warn("Failed to create old_password table: $@") if( $@ );
    eval {
        $dbh->do('ALTER TABLE user ADD COLUMN force_pw_change BOOL NOT NULL DEFAULT 0');
    };
    warn("Failed to add force_pw_change column to user table: $@") if( $@ );
    eval {
        $dbh->do('ALTER TABLE user ADD COLUMN password_changed INT UNSIGNED');
        $dbh->do('UPDATE user SET password_changed = UNIX_TIMESTAMP(NOW())');
    };
    warn("Failed to add password_changed column to user table: $@") if( $@ );

}

# add new krang.conf directive, Charset
sub per_installation {}

1;
