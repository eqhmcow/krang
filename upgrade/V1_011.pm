package V1_011;
use strict;
use warnings;
use base 'Krang::Upgrade';

use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);
use Krang::Schedule;

use File::Spec::Functions qw(catfile);

# Add new krang.conf directive SchedulerMaxChildren
sub per_installation {

    my $self = shift;

    open(CONF, '<', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    my $conf = do { local $/; <CONF> };
    close(CONF);

    # already has a SchedulerMaxChildren setting?
    return if $conf =~ /^\s*SchedulerMaxChildren/m;

    # write out conf and add the new Skin line
    open(CONF, '>', catfile(KrangRoot, 'conf', 'krang.conf'))
      or die "Unable to open conf/krang.conf: $!";
    print CONF $conf;
    print CONF <<END;
#
# Set the number of child processes the scheduler daemon
# can spawn when handling tasks.
# Current wisdom suggests a 3:1 ratio of children to available CPUs.
#
SchedulerMaxChildren 3
END

    close(CONF);

}

sub per_instance {
    my $self = shift;
    my $dbh = dbh();


    ##################################################
    # Scheduler changes

    # The Schedule table has a new column, prioirty.
    # add the new column to table, calculate the priority of every entry.

    # add the column
    $dbh->do("ALTER TABLE schedule ADD COLUMN priority INT UNSIGNED NOT NULL");

    # find all schedule entries, recalculate priority, save.
    foreach my $sched (Krang::Schedule->find()) {
        $sched->priority($sched->determine_priority());
        $sched->save();
    }

    # make sure no 'clean' jobs exist to date.
    foreach my $sched (Krang::Schedule->find(action => 'clean')) {
        $sched->delete();
    }

    # make two new entries:

    # 1) clean the tmp/ directory of anything more than 24 hours old.
    my $schedule = Krang::Schedule->new(
                                        action      => 'clean',
                                        object_type => 'tmp',
                                        repeat      => 'daily',
                                        hour        => 3,
                                        minute      => 0,
                                       );
    $schedule->save();

    # 2) clean out the session table of anything more than 24 hours old.

    $schedule = Krang::Schedule->new(
                                     action      => 'clean',
                                     object_type => 'session',
                                     repeat      => 'daily',
                                     hour        => 3,
                                     minute      => 0
                                    );
    $schedule->save();

    # /Scheduler Changes
    ##################################################

}

1;
