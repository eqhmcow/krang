=head1 NAME

Krang::Schedule - Module for scheduling events in Krang.

=cut

package Krang::Schedule;

use strict;
use warnings;

use Carp qw(verbose croak);
use File::Spec::Functions qw(catdir catfile);
use File::Path qw(rmtree);
use Storable qw/freeze thaw/;
use Time::Piece;
use Time::Piece::MySQL;
use Time::Seconds;

use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);
use Krang::Log qw/ASSERT assert critical debug info/;

use Krang::Alert;
use Krang::Media;
use Krang::Publisher;
use Krang::Story;
use Krang::Template;
use Krang::Cache;



=head1 SYNOPSIS

  use Krang::Schedule;

  # publish a story at a specific date
  $sched = Krang::Schedule->new(object_type => 'story',
                                object_id   => $story_id,
                                action      => 'publish',
                                repeat      => 'never',
                                date        => $date);

  # publish a story at a specific date, specifying the version to be
  # published
  $sched = Krang::Schedule->new(object_type => 'story',
                                object_id   => $story_id,
                                action      => 'publish',
                                context     => [ version => $version ],
                                date        => $date);


  # save the schedule entry to the database
  $sched->save();

  # get the ID for a schedule
  $schedule_id = $schedule->schedule_id;

  # Create an entry to publish a story every Monday at noon.
  $sched = Krang::Schedule->new(object_type => 'story',
                                object_id   => $story_id,
                                action      => 'publish',
                                repeat      => 'weekly',
                                day_of_week => 1,
                                hour        => 12,
                                minute      => 0);


  # Create an entry to publish a story at noon every day.
  $sched = Krang::Schedule->new(object_type => 'story',
                                object_id   => $story_id,
                                action      => 'publish',
                                repeat      => 'daily',
                                hour        => 12,
                                minute      => 0);


  # Create an entry to publish a story every hour on the hour.
  $sched = Krang::Schedule->new(object_type => 'story',
                                object_id   => $story_id,
                                action      => 'publish',
                                repeat      => 'hourly',
                                minute      => 0);


  # get a list of schedule objects for a given story
  @schedules = Krang::Schedule->find(object_type => 'story',
                                     object_id   => 1);


  # load a schedule object by ID
  ($schedule) = Krang::Schedule->find(schedule_id => $schedule_id);

  # get the next execution time of a scheduled event
  $date = $schedule->next_run;

  # get the last execution time of a scheduled event
  $date = $schedule->last_run;


  # execute the task represented by the schedule object
  $success = $schedule->execute();

  # update the next_run field in the schedule object.
  $schedule->update_execution_time();


  # Find the default priority for a Krang::Schedule object
  $priority = Krang::Schedule->determine_priority(schedule => $schedule);

  # or for the current object
  $priority = $schedule->determine_priority();



=head1 DESCRIPTION

This module provides the API into the Krang scheduler.  It is responsible for handling events within Krang that have been scheduled by users.  At this time, those events fall into one of three categories: sending alerts, publishing content (stories and/or media), and expiring content (stories and/or media).

Krang::Schedule is responsible for entering jobs into the system, and for handling the actual execution of a given job.  Determining when to run a job, and the allocation of resources to run that job are handled by L<Krang::Schedule::Daemon>.

=cut


####################
# Package Variables
####################

# Constants
############

# Read-only fields
use constant SCHEDULE_RO => qw(
                               last_run
			       next_run
                               initial_date
			       schedule_id
                              );

# Read-write fields
use constant SCHEDULE_RW => qw(
			       context
			       object_id
                               priority
                              );

# certain fields, when updated, require recalculation of
# priority and next_run for the schedule object.
use constant SCHEDULE_RW_NOTIFY => qw(
                                      action
                                      object_type
                                      repeat
                                      day_of_week
                                      hour
                                      minute
                                     );

# valid actions
use constant ACTIONS => qw(expire publish send clean);
# valid object_types
use constant TYPES => qw(alert media story tmp session analyze);


# Lexicals
###########
my %actions = map {$_, 1} ACTIONS;
my %types = map {$_, 1} TYPES;
my %repeat2seconds = (daily => ONE_DAY,
                      hourly => ONE_HOUR,
                      weekly => ONE_WEEK,
                      never => '');

my %schedule_cols = map {$_ => 1} SCHEDULE_RO, SCHEDULE_RW, SCHEDULE_RW_NOTIFY;
my $tmp_path = catdir(KrangRoot, 'tmp');

# Constructor/Accessor/Mutator setup
use Krang::MethodMaker 
  new_with_init => 'new',
  new_hash_init => 'hash_init',
  get => [SCHEDULE_RO],
  get_set => [SCHEDULE_RW],
  get_set_with_notify => [
                          {
                           method => '_notify',
                           attr   => [SCHEDULE_RW_NOTIFY]
                          }
                         ];



=head1 INTERFACE

=over

=item C<< $sched = Krang::Schedule->new() >>

Create a new schedule object.  The following keys are required:

=over

=item C<action>

The action to be performed.  Must be 'publish', 'expire' or 'send'.

=item C<object_type>

The type of object which the action refers to.  Currently 'story',
'media', and 'alert'.

=item C<object_id>

The ID of the object of type object_type.

=item C<repeat>

Set to the recurrence interval of the action.  Must be 'never',
'hourly', 'daily' or 'weekly'.

=back

The following options are also available:

=over

=item C<date>

A Time::Piece datetime for a scheduled action.  If C<repeat> is set to
'never' then you must set this option.

=item C<hour>

The hour to run a repeating action at.  Required for 'daily' and
'weekly' tasks.  0 indicates 12 midnight.

=item C<minute>

The minute to run a repeating action at.  Required for 'hourly',
'daily' and 'weekly' tasks.

=item C<day_of_week>

The day of the week to run a repeating action at.  Required for
'weekly' tasks.  This is an integer from 0 (Sun) to 6 (Sat).

=item C<context>

An optional array ref containing extra data pertaining to the action
to be performed.

=item C<test_date>

An argument used for testing to abritrarily set the comparison date for
calculating 'next_run' to any point in the past or future.

=item C<priority>

An integer, with acceptable values from 1 to 10 (smaller numbers have higher priority).  By default, priority will vary based on the type of action, the object type, and the whether or not the action is to be repeated.  For instance, a one-time alert will have a priority of 2, a publish task that runs only once will have a priority of 8.

Note that you should not worry about priority, except in special cases.  L<Krang::Schedule::Daemon> handles how jobs will make adjustments to priority if a scheduled task is running late.

=back

=cut

# de facto constructor:
# It croaks if an unexpected argument is passed or if fields necessary for a
# particular schedule type are not passed.  The rules are as follows:
# -if a 'repeat' value of never is passed, a 'date' arg must be supplied with a
#  values that is a Time::Piece object
# -for all other acceptable values for 'repeat', the 'minute' arg must be
#  supplied
# -weekly and daily schedules also require an 'hour' argument
# -weekly schedules require a 'day_of_week' arg

sub init {
    my $self = shift;
    my %args = @_;
    my @bad_args;
    my ($date, $day_of_week, $hour, $minute, $test_date, $priority) =
      map {$args{$_}} qw/date day_of_week hour minute test_date priority/;

    my ($repeat, $action, $object_type);

    my %schedule_args = map {$_ => 1} SCHEDULE_RW, SCHEDULE_RW_NOTIFY, qw/date/;

    # clean actions - object_id isn't used.  Set to 0.
    if (($args{action} eq 'clean') && (!exists($args{object_id}))) {
        $args{object_id} = 0;
    }

    # delete test_date and date -- they aren't actually fields in the object.
    delete $args{date};
    delete $args{test_date};

    for (keys %args) {
        push @bad_args, $_ unless exists $schedule_args{$_};
    }

    croak(__PACKAGE__ . "->init(): The following constructor args are " .
          "invalid: '" . join("', '", @bad_args) . "'") if @bad_args;

    for (qw/action object_id object_type repeat/) {
        croak(__PACKAGE__ . "->init(): Required argument '$_' not present.")
          unless exists $args{$_};
    }

    # NOTE - assignments to $self are usually done by hash_init(), but
    # there are dependencies with get_set_with_notify which need %self populated
    # ahead of time.

    # validate action field.
    $action = lc $args{action};
    croak(__PACKAGE__ . "->init(): '$action' is not a valid 'action'.")
      unless (exists $actions{$action});
    $args{action}   = $action;
    $self->{action} = $action;

    # validate repeat field -- make sure
    $repeat = lc $args{repeat};
    croak(__PACKAGE__ . "->init(): invalid value for 'repeat' field.")
      unless exists $repeat2seconds{$repeat};

    if ($repeat eq 'never') {
        croak(__PACKAGE__ . "->'date' argument required for non-repetitive " .
              "Schedule objects")
          unless $date;
        croak(__PACKAGE__ . "->init():'date' argument must be a Time::Piece object.")
          unless ref $date && $date->isa('Time::Piece');
        $date = $date->mysql_datetime;
    } else {
        croak(__PACKAGE__ . "->init():'minute' argument required for hourly, daily, and " .
              "weekly tasks.")
          unless defined $minute;
        $self->{minute} = $minute;

        if ($repeat =~ /daily|weekly/) {
            croak(__PACKAGE__ . "->init():'hour' argument required for daily and weekly tasks")
              unless defined($hour);
            $self->{hour} = $hour;
        }

        if ($repeat eq 'weekly') {
            croak(__PACKAGE__ . "->init():'day_of_week' required for weekly tasks.")
              unless (defined $day_of_week);
            $self->{day_of_week} = $day_of_week;
        }

    }
    $args{repeat}   = $repeat;
    $self->{repeat} = $repeat;

    # context validation
    if (exists($args{context})) {
        my $context = $args{context};
        croak(__PACKAGE__ . "->init():'context' must be an array reference.")
          unless (ref $context && ref $context eq 'ARRAY');
        # setup field for holding frozen value
        $self->{_frozen_context} = '';
    }

    # object_type validation
    # lowercase object_type to insure consistency for subsequent type
    # testing see lines 792-6
    $object_type = lc $args{object_type};
    croak(__PACKAGE__ . "->init():Invalid object type '$object_type'!") unless
      (exists $types{$object_type});
    $args{object_type}   = $object_type;
    $self->{object_type} = $object_type;

    # set _test_date if submitted.
    if ($test_date) {
        $self->{_test_date} = $test_date;
    }

    $self->hash_init(%args);

    $self->{next_run} = $repeat eq 'never' ? $date :
      $self->_calc_next_run();

    $self->{initial_date} = $self->{next_run};

    # determine priority
    $self->{priority} = $priority ? $priority : $self->determine_priority();


    return $self;
}


# called by get_set_with_notify attributes.
# When anything affecting the priority attribute is changed, recalc priority.
# When anything affecting the next_run attribute is changed, recalc next_run.
sub _notify {
    my ($self, $which, $old, $new) = @_;

    # NOTE - appropriate fields must be defined for repeats.
    if ($which eq 'repeat') {
        if ($new eq 'weekly') {
            croak(__PACKAGE__ . "->repeat(): cannot make 'weekly' without hour, minute, day_of_week set.")
              unless (exists($self->{day_of_week}) && exists($self->{hour}) && exists($self->{minute}));
        } elsif ($new eq 'daily') {
            croak(__PACKAGE__ . "->repeat(): cannot make 'daily' without hour, minute set.")
              unless (exists($self->{hour}) && exists($self->{minute}));
        } elsif ($new eq 'hourly') {
            croak(__PACKAGE__ . "->repeat(): cannot make 'hourly' without minute set.")
              unless (exists($self->{minute}));
        }
    } elsif ($which eq 'action' && ($new eq 'send' || $new eq 'expire')) {
        unless ($self->{repeat} eq 'never') {
            # sanity check - if the new action is an alert or an expire, repeat = never.
            debug(__PACKAGE__ . "->action('$new'): resetting repeat() to 'never'.");
            $self->{repeat} = 'never';
        }
    }

    if ($which =~ /action|object_type|repeat/) {
        $self->{priority} = $self->determine_priority();
    }

    if ($which =~ /repeat|day_of_week|hour|minute/) {
        $self->{next_run} = $self->_calc_next_run();
    }

}




=item C<< determine_priority(schedule => $schedule) >>

Given a L<Krang::Schedule> object, calculates the priority to be assigned to the object.  Returns an integer value from 1-10 (lower the number, higher the priority) representing the priority.  Priority is used by L<Krang::Schedule::Daemon> to determine the order in which scheduled tasks are executed.

Realize that Krang::Schedule::Daemon will raise priority as needed if a scheduled task has not been executed on time.

B<NOTE>: This is not an accessor/mutator - to find the currently-set priority (or to set the priority manually) of a Krang::Schedule object, use C<< $schedule->priority() >>.

Priority is determined based primarily on the C<action> being performed, with C<repeat> and C<object_type> modifying the final result.

=over

=item Alerts

Alerts have a default priority of 2.

=item Expiration

Expiration jobs have a default priority of 4.

=item Publish

Publish jobs have a default priority of 7 for Media objects, 8 for everything else.

=item Clean

Maintenence cleanup jobs have a default priority of 10.

If a job is repeated, the default priority is raised 1 for weekly, 2 for daily, and 3 for hourly.

For example, a story published only once will have a priority of 8 (default), but a media object published hourly would have a priority of 4 (default 7 - 3 for hourly repeats = 4).

=back

=cut

sub determine_priority {
    my $self = shift;
    my %args = @_;

    my $priority;
    my $sched;

    exists($args{schedule}) ? ($sched = $args{schedule}) : ($sched = $self);

    croak(__PACKAGE__ . "->determine_priority(): Missing schedule object!") unless defined($sched);

    my $action = $sched->action();

    if ($action eq 'send') {
        $priority = 2;
    } elsif ($action eq 'expire') {
        $priority = 4;
    } elsif ($action eq 'publish') {
        $priority = ($sched->object_type eq 'media') ? 7 : 8 ;

        my $repeat = $sched->repeat();

        if ($repeat eq 'weekly') {
            $priority -= 1;
        } elsif ($repeat eq 'daily') {
            $priority -= 2;
        } elsif ($repeat eq 'hourly') {
            $priority -= 3;
        }
    } else {
        $priority = 10;
    }

    return $priority;
}



=item C<< $schedule->execute() >>

Runs the task assigned to the C<$schedule> object.  It is assumed that C<execute()> is not being called unless it's appropriate for the job to run at the current time - there is no timestamp sanity checking going on here.

When completed, it will update it's own C<next_run> status as applicable.

Runtime errors (e.g. croaks) are not trapped here - they will be propegated up to the next level.

=cut

sub execute {

    my $self = shift;

    if ($self->{action} eq 'publish') {
        $self->_publish();
    }

    elsif ($self->{action} eq 'expire') {
        $self->_expire();
    }

    elsif ($self->{action} eq 'send') {
        $self->_send();
    }

    elsif ($self->{action} eq 'clean') {
        if ($self->{object_type} eq 'tmp') {
            $self->_clean_tmp();
        }
        elsif ($self->{object_type} eq 'session') {
            $self->_expire_sessions();
        } 
        elsif ($self->{object_type} eq 'analyze') {
            $self->_analyze_db();
        }
        else {
            my $msg = sprintf("%s->execute('clean'): unknown object '%s'", __PACKAGE__, $self->{object_type});
            die($msg);
        }
    }

    else {
        my $msg = sprintf("%s->execute(): unknown action '%s'", __PACKAGE__, $self->{action});
        die($msg);
    }

    if ($self->{repeat} eq 'never') {
        # never to be run again.  delete yourself.
        $self->delete();
    } else {
        # set last_run, update next_run, save.
        $self->{last_run} = $self->{next_run};
        $self->{next_run} = $self->_calc_next_run(skip_match => 1);
        $self->save();
    }

}




#
# _publish()
#
# Takes the story or media object pointed to, and attempts to publish it.
#
# Will return if successful.  It is assumed that failures in the publish process will
# cause things to croak() or die().  If trapped, a Schedule-log entry will be made,
# and the error will be propegated further.
#

sub _publish {

    my $self = shift;

    my $publisher = new Krang::Publisher;

    my $type = $self->object_type();
    my $id   = $self->object_id();
    my $err;
    my %context = defined($self->{context}) ? @{$self->{context}} : ();

    if ($type eq 'media') {
        my @media = Krang::Media->find(media_id => $id, %context);

        unless (@media) {
            my $msg = sprintf("%s->_publish(): Can't find Media id '%i', skipping publish.",
                              __PACKAGE__, $id);
            die($msg);
        }

        eval {
            $publisher->publish_media(media => \@media);
        };

        if (my $err = $@) {
            my $msg = __PACKAGE__ . "->_publish(): error publishing Media ID=$id: $err";
            die $msg;
        }
    }
    elsif ($type eq 'story') {

        my @stories = Krang::Story->find(story_id => $id, %context);

        unless (@stories) {
            my $msg = sprintf("%s->_publish(): Can't find Story id '%i', skipping publish.",
                              __PACKAGE__, $id);
            die($msg);
        }

        # Some stories may have scheduled publishing turned off.
        my @story_publish;

        foreach my $s (@stories) {
            if ($s->element->publish_check()) {
                push @story_publish, $s;
            } else {
                debug(sprintf("%s->_publish(): Story id '%i' has scheduled publish disabled.  Skipping.",
                              __PACKAGE__, $s->story_id()));
            }
        }

        eval {
            $publisher->publish_story(story => \@story_publish, version_check => 0);
        };

        if (my $err = $@) {
            my $msg = __PACKAGE__ . "->_publish(): error publishing Story ID=$id: $err";
            die $msg;
        }

    }

}


#
# _expire()
#
# Runs an expiration job on object_type-object_id.
#
# Will throw a croak() if it cannot find the appropriate object, or
# will propegate errors thrown by the object itself.
#

sub _expire {

    my $self = shift;

    my $object_type = $self->object_type;
    my $object_id   = $self->object_id;
    my $class       = "Krang::" . ucfirst($object_type);

    my ($obj) = $class->find($object_type . '_id' => $object_id);

    unless ($obj) {
        my $msg = sprintf("%s->_expire(): Can't find %s id '%i', skipping expiration.",
                          __PACKAGE__, $class, $object_id);

        die($msg);

    } else {
        $obj->delete;
        debug(__PACKAGE__ . "->_expire(): Deleted $class id '$object_id'.");
    }


}


#
# _send()
#
# Handles the sending of a Krang::Alert.
#
# Will throw any errors propegated by the Krang::Alert system.
#

sub _send {
    my $self = shift;

    my $type    = $self->{object_type};
    my $id      = $self->{object_id};
    my $context = $self->{context};

    eval {
        Krang::Alert->send(alert_id => $id, @$context);
    };

    if (my $err = $@) {
        # log the error
        my $msg = __PACKAGE__ . "->_send(): Attempt to send alert failed: $err";
        die $msg;
    }

    # done.

}




#
# The all-important date calculating sub.
#
# Given the current time, along with parameters to indicate how often
# the job should be repeated, returns a Time::Piece object containing
# the next time that the job should be run.
#
# next_run is based on the value of $now, which is either set by parameter,
# set by _test_date (in debug mode), or determined by localtime().
#
# NOTE: $skip_match is used at runtime - if the calculated next_run ==
# $now, try again, with $now incremented by one second.  This is to
# ensure that if a job finishes and a new next_run is calculated
# before one second has elapsed, it won't get the same time.
#
sub _calc_next_run {
    my $self = shift;
    my %args = @_;

    my ($now, $repeat, $day_of_week, $hour, $minute, $skip_match) =
      @args{qw/now repeat day_of_week hour minute skip_match/};

    # if the _test_date field is set, use that -- but $now trumps!.
    if ($self->{_test_date}) {
        $now = $self->{_test_date} unless $now;
    } else {
        $now = localtime unless $now;
    }

    $repeat      = $self->repeat() unless $repeat;
    $day_of_week = $self->day_of_week() unless $day_of_week;
    $hour        = $self->hour() unless $hour;
    $minute      = $self->minute() unless $minute;

    # sanity check
    $skip_match = 0 unless (defined($args{skip_match}));

    # return the old next_run if there's no repeat.
    return $self->next_run if ($repeat eq 'never');

    my $next = $now;

    # first off, reset seconds to 0.
    if ($next->second > 0) {
        $next += (ONE_MINUTE - $next->second);
    }

    # align minutes -- all cases
    if ($next->minute > $minute) {
        # never roll clock back - roll up to the next hour.
        $next += ( (ONE_HOUR - ($next->minute * ONE_MINUTE) ) + ( $minute * ONE_MINUTE ) );

    } elsif ($next->minute < $minute) {
        # add the minutes up to the next runtime.
        $next += ( ( $minute - $next->minute ) * ONE_MINUTE );
    }

    # align hours -- daily/weekly only
    if ($repeat eq 'daily' || $repeat eq 'weekly') {
        if ($next->hour > $hour) {
            # never roll the clock back.  Roll to the next day.
            $next += ( (ONE_DAY - ($next->hour * ONE_HOUR) ) + ( $hour * ONE_HOUR ) );

        } elsif ($next->hour < $hour) {
            $next += ( ( $hour - $next->hour ) * ONE_HOUR );
        }
    }

    # align days -- weekly only
    if ($repeat eq 'weekly') {
        if ($next->day_of_week > $day_of_week) {
            # never roll the clock back.  Roll to the next week.
            $next += ( (ONE_WEEK - ($next->day_of_week * ONE_DAY) ) + ( $day_of_week * ONE_DAY ) );

        } elsif ($next->day_of_week < $day_of_week) {
            $next += ( ( $day_of_week - $next->day_of_week ) * ONE_DAY );
        }
    }

    if ($skip_match && ($next == $now)) {
        $now += ONE_MINUTE;
        return $self->_calc_next_run(now => $now);
    }

    return $next->mysql_datetime;

}





=item C<< $sched->delete >>

=item C<< Krang::Schedule->delete( $schedule_id ) >>

Removes the schedule from the database.  It will never run again.
This happens to repeat => 'never' schedules automatically after they
are run.

=cut

sub delete {
    my $self = shift;
    my $schedule_id = shift || $self->{schedule_id};

    my $query = "DELETE FROM schedule WHERE schedule_id = ?";
    my $dbh = dbh();
    $dbh->do($query, undef, $schedule_id);

    if (ASSERT) {
        my $count = Krang::Schedule->find(schedule_id => $schedule_id,
                                          count => 1);
        assert($count == 0);
    }

    # return 1 by default for testing
    return 1;
}







#
#
# @deletions = Krang::Schedule->_clean_tmp( max_age => $max_age_hrs )
# @deletions = Krang::Schedule->_clean_tmp()
#
# Class method that will remove all files in $KRANG_ROOT/tmp older than
# $max_age_in_hours.  If no parameter is passed file and directories older than
# 24 hours will be removed.  This method will croak if it
# is unable to delete a file or directory.  Returns a list of files and
# directories deleted.
#
#
sub _clean_tmp {

    my $self = shift;
    my %args = @_;
    my $max_age = ( exists ($args{max_age}) ) ? $args{max_age} : 24;

    my (@dirs, @files);

    my $date = ( exists($self->{_test_date}) ) ? $self->{_test_date} : localtime;
    $date = $date - ($max_age * ONE_HOUR);

    debug(__PACKAGE__ . "->_clean_tmp(): looking to delete files in tmp/ older than " . $date->mysql_datetime);

    # build a list of files to delete
    opendir(DIR, $tmp_path) || croak(__PACKAGE__ . "->_clean_tmp(): Can't open tmpdir: $!");
    for (readdir DIR) {
        # skip the protected files
        next if $_ =~ /(CVS|\.{1,2}|\.(conf|cvsignore|pid))$/;

        # skip them if they're too young
        my $file = catfile($tmp_path, $_);
        my $mtime = Time::Piece->new((stat($file))[9]);
        next unless ($mtime - $date) <= 0;

        if (-f $file) {
            push @files, $file;
        } elsif (-d $file) {
            push @dirs, $file;
        }
    }
    closedir(DIR);

    # handle warnings generated by File::Path
    local $SIG{__WARN__} = sub {debug(__PACKAGE__ . "->clean_tmp(): " . $_[0]);};

    # list of files deleted
    my @deletions;

    # delete files
    for (@files) {
        unless (unlink $_) {
            critical(__PACKAGE__ . "->_clean_tmp(): Unable to delete '$_': $!");
        } else {
            debug(__PACKAGE__ . "->_clean_tmp(): deleted file '$_'");
            push @deletions, $_;
        }
    }

    # delete directories
    for my $dir (@dirs) {
        rmtree([$dir], 1, 1);
        if (-e $dir) {
            critical("Unable to delete '$dir'.");
        } else {
            debug(__PACKAGE__ . "->_clean_tmp(): deleted dir '$dir'");
            push @deletions, $dir;
        }
    }

    return @deletions;
}





#
# @ids = Krang::Schedule->expire_sessions( max_age => $max_age_hrs )
#
# @ids = Krang::Schedule->expire_sessions()
#
# Class method that deletes sessions from the sessions table whose
# 'last_modified' field contains a value less than 'now() - INTERVAL
# $max_age_in_hours HOUR'.  Returns a list of the session ids that have been
# expired.
#
# If max_age is not supplied, defaults to 24 hours.
#

sub _expire_sessions {
    my $self = shift;
    my %args = @_;
    my $max_age = exists $args{max_age} ? $args{max_age} : 24;
    my $dbh = dbh();
    my ($i, @ids, $query);

    # get deletion candidates
    $query = <<SQL;
SELECT id
FROM sessions
WHERE last_modified < now() - INTERVAL ? HOUR
SQL
    my $row_refs = $dbh->selectall_arrayref($query, undef, $max_age);
    for $i(0..$#{@$row_refs}) {
        push @ids, $row_refs->[$i][0];
    }

    # destroy them
    if (@ids) {
        $query = "DELETE FROM sessions WHERE " .
          join(" OR ", map {"id = ?"} @ids);
        $dbh->do($query, undef, @ids);

        # log destruction
        debug(__PACKAGE__ . "->_expire_sessions(): Deleted the following Expired Session IDs: (" . 
             join(" ", @ids) . ")");

        return @ids;
    }
}

#
# _analyze_db() - analyzes all database tables for maximum performance
#
sub _analyze_db {
    my $dbh = dbh();
    
    my $tables = $dbh->selectcol_arrayref('show tables');
    foreach my $table (@$tables) {
        debug("Analyzing table $table.");
        $dbh->do("ANALYZE TABLE $table");
    }
}

=item @schedules = Krang::Schedule->find(...)

Finds schedules in the database based on supplied criteria.

Fields may be matched using SQL matching.  Appending "_like" to a
field name will specify a case-insensitive SQL match.

Available search options are:

=over

=item action

=item initial_date

=item last_run

=item next_run

'next_run' also supports the following variations for date comparisons:

=over

=item next_run_greater

=item next_run_less

=item next_run_greater_than_or_equal

=item next_run_less_than_or_equal

=back

=item object_id

=item object_type

=item schedule_id

=back

Options affecting the search and the results returned:

=over

=item ids_only

Return only IDs, not full story objects.

=item count

Return just a count of the results for this query.

=item limit

Return no more than this many results.

=item offset

Start return results at this offset into the result set.

=item order_by

Output field to sort by.  Defaults to 'schedule_id'.

=item order_desc

Results will be in sorted in ascending order unless this is set to 1
(making them descending).

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my ($fields, @params, $where_clause);

    # grab ascend/descending, limit, and offset args
    my $ascend = delete $args{order_desc} ? 'DESC' : 'ASC';
    my $limit = delete $args{limit} || '';
    my $offset = delete $args{offset} || '';
    my $order_by = delete $args{order_by} || 'schedule_id';

    # set search fields
    my $count = delete $args{count} || '';
    my $ids_only = delete $args{ids_only} || '';

    # set bool to determine whether to use $row or %row for binding below
    my $single_column = $ids_only || $count ? 1 : 0;

    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.") if ($count && $ids_only);

    # exclude 'element'
    $fields = $count ? 'count(*)' :
      ($ids_only ? 'schedule_id' : join(", ", keys %schedule_cols));

    # set up WHERE clause and @params, croak unless the args are in
    # SCHEDULE_RO, SCHEDULE_RW or SCHEDULE_RW_NOTIFY.
    my @invalid_cols;
    for my $arg (keys %args) {
        my $like = 1 if $arg =~ /_like$/;
        ( my $lookup_field = $arg ) =~ s/^(.+)_like$/$1/;

        push @invalid_cols, $arg
          unless (exists $schedule_cols{$lookup_field} || $arg =~ /^next_run/);

        if ($arg eq 'schedule_id' && ref $args{$arg} eq 'ARRAY') {
            my $tmp = join(" OR ", map {"schedule_id = ?"} @{$args{$arg}});
            $where_clause .= " ($tmp)";
            push @params, @{$args{$arg}};
        }
        # handle next_run date comparisons
        elsif ($arg =~ /^next_run_(.+)$/) {
            my @gtltargs = split(/_/, $1);

            croak("'$arg' is and invalid 'next_run' field comparison.")
              unless ($gtltargs[0] eq 'greater' ||
                      $gtltargs[0] eq 'less' ||
                      scalar @gtltargs == 1 ||
                      scalar @gtltargs == 3);

            my $operator = $gtltargs[0] eq 'greater' ? '>' : '<';
            $operator .= '=' if scalar @gtltargs == 3;

            $where_clause .= "next_run $operator ";
            if ($args{$arg} eq 'now()') {
                $where_clause .= 'now()';
            } else {
                $where_clause .= '?';
                push @params, $args{$arg};
            }

        } else {
            my $and = defined $where_clause && $where_clause ne '' ?
              ' AND' : '';
            if (not defined $args{$arg}) {
                $where_clause .= "$and $lookup_field IS NULL";
            } else {
                $where_clause .= $like ? "$and $lookup_field LIKE ?" :
                  "$and $lookup_field = ?";
                push @params, $args{$arg};
            }
        }
    }

    croak("The following passed search parameters are invalid: '" .
          join("', '", @invalid_cols) . "'") if @invalid_cols;

    # construct base query
    my $query = "SELECT $fields FROM schedule";

    # add WHERE and ORDER BY clauses, if any
    $query .= " WHERE $where_clause" if $where_clause;
    $query .= " ORDER BY $order_by $ascend" if $order_by;

    # add LIMIT clause, if any
    if ($limit) {
        $query .= $offset ? " LIMIT $offset, $limit" : " LIMIT $limit";
    } elsif ($offset) {
        $query .= " LIMIT $offset, -1";
    }

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);

    debug(__PACKAGE__."->find() SQL: $query");
    debug(__PACKAGE__."->find() SQL ARGS: @params");

    $sth->execute(@params);

    # holders for query results and new objects
    my ($row, @schedules);

    # bind fetch calls to $row or %$row
    # a possibly insane micro-optimization :)
    if ($single_column) {
        $sth->bind_col(1, \$row);
    } else {
        $sth->bind_columns(\( @$row{@{$sth->{NAME_lc}}} ));
    }

    # construct category objects from results
    while ($sth->fetchrow_arrayref()) {
        # if we just want count or ids
        if ($single_column) {
            push @schedules, $row;
        } else {
            push @schedules, bless({%$row}, $self);
        }
    }

    # thaw contexts, if necessary
    unless ($count or $ids_only) {
        for (@schedules) {
            # store frozen value in '_frozen_context'
            $_->{_frozen_context} = $_->{context};
            eval {$_->{context} = thaw($_->{context})};
            croak(__PACKAGE__ . "->find(): Unable to thaw context: $@") if $@;
        }
    }

    # return number of rows if count, otherwise an array of ids or objects
    return $count ? $schedules[0] : @schedules;
}



=item C<< $sched->save >>

Saves the schedule to the database.  It will now be run at its
appointed hour.

=cut

sub save {
    my $self = shift;
    my $id = $self->{schedule_id} || 0;
    my @save_fields = grep {$_ ne 'schedule_id'} keys %schedule_cols;
    my ($query);

    # validate 'repeat'
    croak(__PACKAGE__ . "->save(): 'repeat' field set to invalid setting - " .
          "$self->{repeat}")
      unless exists $repeat2seconds{$self->{repeat}};

    # freeze context in '_frozen_context'
    my $context = $self->{context};
    if ($context) {
        croak(__PACKAGE__ . "->save(): 'context' field is not an array ref")
          unless (ref $self->{context} && ref $self->{context} eq 'ARRAY');

        eval {$self->{_frozen_context} = freeze($context)};
        croak(__PACKAGE__ . "->save(): Unable to freeze context: $@") if $@;
    }

    # the object has already been saved once if $id
    if ($id) {
        $query = "UPDATE schedule SET " .
          join(", ", map {"$_ = ?"} @save_fields) .
            " WHERE schedule_id = ?";
    } else {
        # build insert query
        $query = "INSERT INTO schedule (" . join(',', @save_fields) .
          ") VALUES (?" . ", ?" x (scalar @save_fields - 1) . ")";
    }

    # bind parameters
    my @params = map {$context && $_ eq 'context' ?
                        $self->{_frozen_context} :
                          $self->{$_}}
      @save_fields;

    # need user_id for updates
    push @params, $id if $id;

    # croak if no rows are affected
    my $dbh = dbh();
    croak(__PACKAGE__ . "->save(): Unable to save Schedule object " .
          ($id ? "id '$id' " : '') . "to the DB.")
      unless $dbh->do($query, undef, @params);

    $self->{schedule_id} = $dbh->{mysql_insertid} unless $id;

    return $self;
}





=item $schedule->serialize_xml(writer => $writer, set => $set)

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self, %args) = @_;
    my ($writer, $set) = @args{qw(writer set)};
    local $_;

    # open up <schedule> linked to schema/schedule.xsd
    $writer->startTag('schedule',
                      "xmlns:xsi" =>
                        "http://www.w3.org/2001/XMLSchema-instance",
                      "xsi:noNamespaceSchemaLocation" =>
                        'schedule.xsd');

    $writer->dataElement( schedule_id => $self->{schedule_id} );
    $writer->dataElement( object_type => $self->{object_type} );
    $writer->dataElement( object_id => $self->{object_id} );
    $writer->dataElement( action => $self->{action} );
    $writer->dataElement( repeat => $self->{repeat} );
    my $next_run = $self->{next_run} || '';
    $next_run =~ s/\s/T/;
    $writer->dataElement( next_run => $next_run );
    my $last_run = $self->{last_run} || '';
    $last_run =~ s/\s/T/;
    $writer->dataElement( last_run => $last_run ) if $self->{last_run};
    my $initial_date = $self->{initial_date} || '';
    $initial_date =~ s/\s/T/;
    $writer->dataElement( initial_date => $initial_date );
    $writer->dataElement( hour => $self->{hour} ) if defined $self->{hour};
    $writer->dataElement( minute => $self->{minute} )
      if defined $self->{minute};
    $writer->dataElement( day_of_week => $self->{day_of_week} )
      if defined $self->{day_of_week};

    $writer->dataElement( priority => $self->{priority} );

    # context
    if (my $context = $self->{context}) {
        my %c_hash = @$context;
        for my $key (keys %c_hash ) {
            $writer->startTag('context');
            $writer->dataElement( key => $key );
            $writer->dataElement( value => $c_hash{$key} );
            $writer->endTag('context');

            $set->add(object =>($Krang::User->find(user_id =>
                                                   $c_hash{user_id}))[0],
                      from => $self)
              if ($key eq 'user_id');
        }
    }

    # all done
    $writer->endTag('schedule');
}


=item C<< $schedule = Krang::Schedule->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML.  See Krang::DataSet for details.

If an incoming schedule has matching fields with an existing schedule, it
is ignored (not duplicated).

Note that last_run is not imported, next_run is translated to 'date'.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set) = @args{qw(xml set)};

    # divide FIELDS into simple and complex groups
    my (%complex, %simple);

    # strip out all fields we don't want updated or used.
    @complex{qw(schedule_id object_id last_run context next_run initial_date)}
      = ();
    %simple = map { ($_,1) } grep { not exists $complex{$_} }
      (SCHEDULE_RO,SCHEDULE_RW,SCHEDULE_RW_NOTIFY);

    # parse it up
    my $data = Krang::XML->simple(xml           => $xml,
                                  suppressempty => 1);

    my $new_id = $set->map_id(class => "Krang::".ucfirst($data->{object_type}),
                              id => $data->{object_id});

    my $initial_date = $data->{initial_date};
    $initial_date =~ s/T/ /;

    my %search_params = ( object_type => $data->{object_type},
                          object_id => $new_id,
                          action => $data->{action},
                          repeat => $data->{repeat},
                          initial_date => $initial_date );

    $initial_date = Time::Piece->from_mysql_datetime($initial_date);
    $search_params{hour} = $data->{hour} if $data->{hour};
    $search_params{minute} = $data->{minute} if $data->{minute};
    $search_params{day_of_week} = $data->{day_of_week} if $data->{day_of_week};

    debug(__PACKAGE__."->deserialize_xml() : finding schedules with params- ".
          join(',', (map { $search_params{$_} } keys %search_params) ));

    # is there an existing object?
    my $schedule = (Krang::Schedule->find( %search_params ))[0] || '';

    if (not $schedule) {
        $schedule = Krang::Schedule->new(   object_id => $new_id,
                                            date => $initial_date,
                                            (map {($_,$data->{$_})}
                                             keys %simple));
        $schedule->save;
    }

    return $schedule;
}




#
# accessor/mutator for internal _test_date field.
# used for testing purposes ONLY.
#
sub _test_date {
    my $self = shift;
    return $self->{_test_date} unless @_;

    $self->{_test_date} = $_[0];

}





=back

=cut


"JAPH";

