package V2_008;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader Conf => 'KrangRoot';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'UUID';
use File::Spec::Functions qw(catfile);

# nothing yet
sub per_instance {
    my $self = shift;

    my $dbh = dbh();

    # add new tables and data for login security
    print "Adding rate_limit_hits table and scheduling cleanup task\n";
    eval {
        $dbh->do(
            q(
            CREATE TABLE rate_limit_hits (
               user_id   VARCHAR(255)      NOT NULL,
               action    VARCHAR(255)      NOT NULL,
               timestamp INTEGER UNSIGNED NOT NULL,
               INDEX (user_id(15), action(30), timestamp)
            ) TYPE=MyISAM;
        ));
    };
    eval {
        $dbh->do(
            q(
            INSERT INTO schedule
             (`repeat`, action, object_type, initial_date, last_run, next_run, hour, minute)
            VALUES
             ('daily', 'clean', 'rate_limit', NOW(), NOW(), NOW(), 3, 0);
        ));
    };
    warn("Failed to schedule rate_limit cleanup: $@") if ($@);
    eval {
        $dbh->do(
            q(
            CREATE TABLE old_password (
                    user_id     INT UNSIGNED NOT NULL,
                    password    VARCHAR(255) NOT NULL,
                    timestamp   INT UNSIGNED,
                    KEY (user_id),
                    PRIMARY KEY (user_id, password)
            );
        ));
    };
    warn("Failed to create old_password table: $@") if ($@);
    eval {
        $dbh->do(
'ALTER TABLE user ADD COLUMN force_pw_change BOOL NOT NULL DEFAULT 0');
    };
    warn("Failed to add force_pw_change column to user table: $@") if ($@);
    eval {
        $dbh->do('ALTER TABLE user ADD COLUMN password_changed INT UNSIGNED');
        $dbh->do('UPDATE user SET password_changed = UNIX_TIMESTAMP(NOW())');
    };
    warn("Failed to add password_changed column to user table: $@") if ($@);

    # add UUID columns
    foreach my $table (qw(story media template site category user group)) {
        eval {
            $dbh->do(  "ALTER TABLE $table ADD COLUMN "
                     . "${table}_uuid CHAR(36) NOT NULL");
        };
        warn("Failed to add ${table}_uuid column to $table table: $@") if $@;

        eval {
            my $unique = $table eq 'group' ? "UNIQUE" : "";
            $dbh->do(  "CREATE $unique INDEX ${table}_uuid_index "
                     . "ON $table (${table}_uuid)");
        };
        warn("Failed to add index for ${table}_uuid column: $@") if $@;

        # give all objects a distinct UUID, could take a while for
        # large tables
        print "Creating new UUIDs in $table table...\n";
        eval {
            my $ids =
              $dbh->selectcol_arrayref("SELECT ${table}_id FROM $table");
            my $set_sth =
              $dbh->prepare(
                 "UPDATE $table SET ${table}_uuid = ? WHERE ${table}_id = ?");
            foreach my $id (@$ids) {
                $set_sth->execute(pkg('UUID')->new(), $id);
            }
        };
        warn("Failed to set ${table}_uuid values in $table table: $@") if $@;
    }
}

# nothing yet
sub per_installation { }

1;
