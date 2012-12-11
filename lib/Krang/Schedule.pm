
=head1 NAME

Krang::Schedule - Module for scheduling events in Krang.

=cut

package Krang::Schedule;

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Carp qw(verbose croak);
use File::Spec::Functions qw(catdir catfile);
use File::Path qw(rmtree);
require File::Find;    # File::Find exports a find() method if we use 'use'.

use Storable qw/nfreeze thaw/;
use Time::Piece;
use Time::Piece::MySQL;
use Time::Seconds;

use Krang::ClassLoader Conf => qw(KrangRoot);
use Krang::ClassLoader DB   => qw(dbh);
use Krang::ClassLoader Log  => qw(ASSERT assert critical debug info);

use Krang::ClassLoader 'Alert';
use Krang::ClassLoader 'Media';
use Krang::ClassLoader 'Publisher';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'Template';
use Krang::ClassLoader 'Cache';

=head1 SYNOPSIS

    use Krang::ClassLoader 'Schedule';

    # publish a story at a specific date
    $sched = pkg('Schedule')->new(
        object_type => 'story',
        object_id   => $story_id,
        action      => 'publish',
        repeat      => 'never',
        date        => $date
    );

    # publish a story at a specific date, specifying the version to be
    # published
    $sched = pkg('Schedule')->new(
        object_type => 'story',
        object_id   => $story_id,
        action      => 'publish',
        context     => [version => $version],
        date        => $date
    );

    # publish a story at a specific date, specifying a limit to the number of 
    # attempts, a delay (in seconds) between each attempt, and the ID for a user
    # who should be emailed after failure/success
    $sched = pkg('Schedule')->new(
        object_type => 'story',
        object_id   => $story_id,
        action      => 'publish',
        date        => $date,
        failure_max_tries => 4,    # try a maximum of 4 times before giving up
        failure_delay_sec => 600,  # wait 10 minutes between each try
        failure_notify_id => 2,    # if all 4 attempts fail, email user 2 to notify him/her
        success_notify_id => 2,    # if any attempt succeeds, email user 2 to notify him/her
    );

    # save the schedule entry to the database
    $sched->save();

    # get the ID for a schedule
    $schedule_id = $schedule->schedule_id;

    # Create an entry to publish a story every Monday at noon.
    $sched = pkg('Schedule')->new(
        object_type => 'story',
        object_id   => $story_id,
        action      => 'publish',
        repeat      => 'weekly',
        day_of_week => 1,
        hour        => 12,
        minute      => 0
    );

    # Create an entry to publish a story at noon every day.
    $sched = pkg('Schedule')->new(
        object_type => 'story',
        object_id   => $story_id,
        action      => 'publish',
        repeat      => 'daily',
        hour        => 12,
        minute      => 0
    );

    # Create an entry to publish a story every hour on the hour.
    $sched = pkg('Schedule')->new(
        object_type => 'story',
        object_id   => $story_id,
        action      => 'publish',
        repeat      => 'hourly',
        minute      => 0
    );

    # Create an entry to publish a story every hour on the hour.
    $sched = pkg('Schedule')->new(
        object_type => 'story',
        object_id   => $story_id,
        action      => 'publish',
        repeat      => 'hourly',
        minute      => 0
    );

    # get a list of schedule objects for a given story
    @schedules = pkg('Schedule')->find(
        object_type => 'story',
        object_id   => 1
    );

    # load a schedule object by ID
    ($schedule) = pkg('Schedule')->find(schedule_id => $schedule_id);

    # get the next execution time of a scheduled event
    $date = $schedule->next_run;

    # get the last execution time of a scheduled event
    $date = $schedule->last_run;

    # execute the task represented by the schedule object
    $success = $schedule->execute();

    # update the next_run field in the schedule object.
    $schedule->update_execution_time();

    # Find the default priority for a Krang::Schedule object
    $priority = pkg('Schedule')->determine_priority(schedule => $schedule);

    # or for the current object
    $priority = $schedule->determine_priority();

=head1 DESCRIPTION

This module provides the API into the Krang scheduler.  It is responsible
for handling events within Krang that have been scheduled by users.
At this time, those events fall into one of three categories: sending
alerts, publishing content (stories and/or media), and expiring content
(stories and/or media).

Krang::Schedule is responsible for entering jobs into the system, and
for handling the actual execution of a given job.  Determining when to
run a job, and the allocation of resources to run that job are handled
by L<Krang::Schedule::Daemon>.

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
  expires
  inactive
  failure_max_tries
  failure_delay_sec
  failure_notify_id
  success_notify_id
  daemon_uuid
);

# certain fields, when updated, require recalculation of
# priority and next_run for the schedule object.
use constant SCHEDULE_RW_NOTIFY => qw(
  action
  object_type
  repeat
  day_of_month
  day_of_week
  day_interval
  hour
  minute
);

# Lexicals
###########
my %repeat2seconds = (
    daily    => ONE_DAY,
    hourly   => ONE_HOUR,
    weekly   => ONE_WEEK,
    monthly  => '',
    interval => '',
    never    => ''
);

my %schedule_cols = map { $_ => 1 } SCHEDULE_RO, SCHEDULE_RW, SCHEDULE_RW_NOTIFY;
my $tmp_path = catdir(KrangRoot, 'tmp');

# Constructor/Accessor/Mutator setup
use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get                              => [SCHEDULE_RO],
  get_set                          => [SCHEDULE_RW],
  get_set_with_notify              => [
    {
        method => '_notify',
        attr   => [SCHEDULE_RW_NOTIFY]
    }
  ];

sub id_meth { 'schedule_id' }

=head1 INTERFACE

=over

=item C<< $sched = pkg('Schedule')->new() >>

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

Set to the recurrence interval of the action.  Must be C<never>, C<hourly>,
C<daily>, C<weekly>, C<monthly> or C<interval>.

=back

The following options are also available:

=over

=item C<date>

A L<Time::Piece> datetime for a scheduled action.  If C<repeat> is set to
'never' then you must set this option.

=item C<hour>

The hour to run a repeating action at.  Required for C<daily> and
C<weekly> tasks. 0 indicates 12 midnight.

=item C<minute>

The minute to run a repeating action at.  Required for C<hourly>, C<daily>
and C<weekly> tasks.

=item C<day_of_week>

The day of the week to run a repeating action at.  Required for C<weekly>
tasks.  This is an integer from 0 (Sun) to 6 (Sat).

=item C<day_of_month>

The day of the month to run a repeating action at. Required for C<monthly>
tasks. This is an integer set from 1 to 28, or from -1 to -28. Positive values
represent the first 28 days of each month. Negative values count backwards 
from the last day of the month, with -1 being the last day, -2 being the second 
to last day, etc.

=item C<day_interval>

The number of days between each run. Required for C<interval> tasks. This is 
a positive integer.

=item C<context>

An optional array ref containing extra data pertaining to the action to
be performed.

=item C<test_date>

An argument used for testing to abritrarily set the comparison date for
calculating 'next_run' to any point in the past or future.

=item C<priority>

An integer, with acceptable values from 1 to 10 (smaller numbers have
higher priority).  By default, priority will vary based on the type
of action, the object type, and the whether or not the action is to
be repeated.  For instance, a one-time alert will have a priority of 2,
a publish task that runs only once will have a priority of 8.

Note that you should not worry about priority, except in special cases.
L<Krang::Schedule::Daemon> handles how jobs will make adjustments to
priority if a scheduled task is running late.

=item C<inactive>

If set to 1, the schedule will not be executed. Defaults to 0.

=item C<daemon_uuid>

The Krang::UUID of the daemon processing the schedule. Used internally
to allow multiple schedule daemons to run without interfering with
each other or process the same schedule.

=back

=cut

# de facto constructor:
# It croaks if an unexpected argument is passed or if fields necessary for a
# particular schedule type are not passed.  The rules are as follows:
# -if a 'repeat' value of never or interval is passed, a 'date' arg must be
#  supplied with a values that is a Time::Piece object
# -for all other acceptable values for 'repeat', the 'minute' arg must be
#  supplied
# -interval, monthly, weekly and daily schedules also require an 'hour' argument
# -weekly schedules require a 'day_of_week' arg
# -monthly schedules require a 'day_of_month' arg
# -interval schedules require a 'day_interval' arg.
# -option expiration of schedule requires an 'expires' arg that is a Time::Piece
#  object

sub init {
    my $self = shift;
    my %args = @_;
    my @bad_args;
    my (
        $date,   $day_of_month, $day_of_week, $day_interval, $hour,
        $minute, $expires,      $test_date,   $priority
      )
      = map { $args{$_} }
      qw/date day_of_month day_of_week day_interval hour minute expires test_date priority/;

    # per default a schedule is active
    $args{inactive} = 0 unless defined($args{inactive});

    my ($repeat, $action, $object_type);

    my %schedule_args = map { $_ => 1 } SCHEDULE_RW, SCHEDULE_RW_NOTIFY, qw/date/;

    # clean actions - object_id isn't used.  Set to 0.
    if (($args{action} eq 'clean') && (!exists($args{object_id}))) {
        $args{object_id} = 0;
    }

    ##
    $args{object_id} ||= 0;

    # delete test_date and date -- they aren't actually fields in the object.
    delete $args{date};
    delete $args{test_date};

    for (keys %args) {
        push @bad_args, $_ unless exists $schedule_args{$_};
    }

    croak(  __PACKAGE__
          . "->init(): The following constructor args are "
          . "invalid: '"
          . join("', '", @bad_args) . "'")
      if @bad_args;

    for (qw/action object_id object_type repeat/) {
        croak(__PACKAGE__ . "->init(): Required argument '$_' not present.")
          unless exists $args{$_};
    }

    # NOTE - assignments to $self are usually done by hash_init(), but
    # there are dependencies with get_set_with_notify which need %self populated
    # ahead of time.

    # validate action field.
    $action         = lc $args{action};
    $args{action}   = $action;
    $self->{action} = $action;

    # validate repeat field -- make sure
    $repeat = lc $args{repeat};
    croak(__PACKAGE__ . "->init(): invalid value for 'repeat' field.")
      unless exists $repeat2seconds{$repeat};

    if ($repeat eq 'never') {
        croak(__PACKAGE__ . "->'date' argument required for non-repetitive tasks")
          unless $date;
        croak(__PACKAGE__ . "->init():'date' argument must be a Time::Piece object.")
          unless ref $date && $date->isa('Time::Piece');
        $date = $date->mysql_datetime;
    } elsif ($repeat eq 'interval') {
        croak(__PACKAGE__ . "->'date' argument required for interval tasks")
          unless $date;
        croak(__PACKAGE__ . "->init():'date' argument must be a Time::Piece object.")
          unless ref $date && $date->isa('Time::Piece');
        $date = $date->mysql_datetime;
        $self->{day_interval} = $day_interval;
    } else {
        croak(  __PACKAGE__
              . "->init():'minute' argument required for hourly, daily, "
              . "weekly, and monthly tasks.")
          unless defined $minute;
        $self->{minute} = $minute;

        if ($repeat =~ /daily|weekly|monthly/) {
            croak(__PACKAGE__
                  . "->init():'hour' argument required for daily, weekly, and monthly tasks")
              unless defined($hour);
            $self->{hour} = $hour;
        }

        if ($repeat eq 'weekly') {
            croak(__PACKAGE__ . "->init():'day_of_week' required for weekly tasks.")
              unless (defined $day_of_week);
            $self->{day_of_week} = $day_of_week;
        }

        if ($repeat eq 'monthly') {
            croak(__PACKAGE__ . "->init():'day_of_month' required for monthly tasks.")
              unless (defined $day_of_month);
            $self->{day_of_month} = $day_of_month;
        }

    }
    $args{repeat} = $repeat;
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
    my %types = $self->_allowable_object_types;
    croak(__PACKAGE__ . "->init():Invalid object type '$object_type'!")
      unless (exists $types{$object_type});
    $args{object_type} = $object_type;
    $self->{object_type} = $object_type;

    # set _test_date if submitted.
    if ($test_date) {
        $self->{_test_date} = $test_date;
    }

    if ($expires) {
        $self->{expires} = $expires->mysql_datetime;
        delete $args{expires};
    }

    $self->{next_run} =
      ($repeat eq 'never' or $repeat eq 'interval')
      ? $date
      : $self->_calc_next_run();

    $self->{initial_date} = $self->{next_run};

    # this used to be above the prior block, but interval needs these
    # dates set first
    $self->hash_init(%args);

    # but hash_init updates next run, which interval doesn't need
    if ($repeat eq 'interval') {
        $self->{next_run} = $self->{initial_date};
    }

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
        if ($new eq 'interval') {
            croak(__PACKAGE__ . "->repeat(): cannot make 'interval' without day_interval set.")
              unless (exists($self->{day_interval}));
        } elsif ($new eq 'monthly') {
            croak(__PACKAGE__
                  . "->repeat(): cannot make 'monthly' without hour, minute, day_of_month set.")
              unless (exists($self->{day_of_month})
                && exists($self->{hour})
                && exists($self->{minute}));
        } elsif ($new eq 'weekly') {
            croak(__PACKAGE__
                  . "->repeat(): cannot make 'weekly' without hour, minute, day_of_week set.")
              unless (exists($self->{day_of_week})
                && exists($self->{hour})
                && exists($self->{minute}));
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

    if ($which =~ /repeat|day_of_month|day_of_week|day_interval|hour|minute/) {
        $self->{next_run} = $self->_calc_next_run();
    }

}

=item C<< determine_priority(schedule => $schedule) >>

Given a L<Krang::Schedule> object, calculates the priority to be assigned
to the object.  Returns an integer value from 1-10 (lower the number,
higher the priority) representing the priority.  Priority is used by
L<Krang::Schedule::Daemon> to determine the order in which scheduled
tasks are executed.

Realize that L<Krang::Schedule::Daemon> will raise priority as needed
if a scheduled task has not been executed on time.

B<NOTE>: This is not an accessor/mutator - to find the currently-set
priority (or to set the priority manually) of a Krang::Schedule object,
use C<< $schedule->priority() >>.

Priority is determined based primarily on the C<action> being performed,
with C<repeat> and C<object_type> modifying the final result.

=over

=item Alerts

Alerts have a default priority of 2.

=item Expiration

Expiration jobs have a default priority of 4.

=item Publish

Publish jobs have a default priority of 7 for Media objects, 8 for
everything else.

=item Clean

Maintenence cleanup jobs have a default priority of 10.

If a job is repeated, the default priority is raised 1 for weekly,
2 for daily, and 3 for hourly.

For example, a story published only once will have a priority of 8
(default), but a media object published hourly would have a priority of 4
(default 7 - 3 for hourly repeats = 4).

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
        $priority = ($sched->object_type eq 'media') ? 7 : 8;

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

    my ($now, $repeat, $day_of_month, $day_of_week, $day_interval, $hour, $minute, $skip_match) =
      @args{qw/now repeat day_of_month day_of_week day_interval hour minute skip_match/};

    # if the _test_date field is set, use that -- but $now trumps!.
    if ($self->{_test_date}) {
        $now = $self->{_test_date} unless $now;
    } else {
        $now = localtime unless $now;
    }

    $repeat       = $self->repeat()       unless $repeat;
    $day_of_month = $self->day_of_month() unless $day_of_month;
    $day_of_week  = $self->day_of_week()  unless $day_of_week;
    $day_interval = $self->day_interval() unless $day_interval;
    $hour         = $self->hour()         unless $hour;
    $minute       = $self->minute()       unless $minute;

    # sanity check
    $skip_match = 0 unless (defined($args{skip_match}));

    # return the old next_run if there's no repeat.
    return $self->next_run if ($repeat eq 'never');

    my $next = $now;

    if ($repeat ne 'interval') {

        # first off, reset seconds to 0.
        if ($next->second > 0) {
            $next += (ONE_MINUTE - $next->second);
        }

        # align minutes -- all cases
        if ($next->minute > $minute) {

            # never roll clock back - roll up to the next hour.
            $next += ((ONE_HOUR - ($next->minute * ONE_MINUTE)) + ($minute * ONE_MINUTE));

        } elsif ($next->minute < $minute) {

            # add the minutes up to the next runtime.
            $next += (($minute - $next->minute) * ONE_MINUTE);
        }

        # align hours -- all except hourly
        if (   $repeat eq 'daily'
            || $repeat eq 'weekly'
            || $repeat eq 'monthly'
            || $repeat eq 'interval')
        {
            if ($next->hour > $hour) {

                # never roll the clock back.  Roll to the next day.
                $next += ((ONE_DAY - ($next->hour * ONE_HOUR)) + ($hour * ONE_HOUR));

            } elsif ($next->hour < $hour) {
                $next += (($hour - $next->hour) * ONE_HOUR);
            }
        }

        # align day of week -- weekly only
        if ($repeat eq 'weekly') {
            if ($next->day_of_week > $day_of_week) {

                # never roll the clock back.  Roll to the next week.
                $next += ((ONE_WEEK - ($next->day_of_week * ONE_DAY)) + ($day_of_week * ONE_DAY));

            } elsif ($next->day_of_week < $day_of_week) {
                $next += (($day_of_week - $next->day_of_week) * ONE_DAY);
            }
        }

        # align day of month -- monthly only
        if ($repeat eq 'monthly') {

            # we need to jump thru some hoops to get a negative day_of_month positive
            if ($day_of_month < 0) {
                my $this_last_day = $self->_last_day_of_month($next->mon, $next->year);
                my $pos_day = $this_last_day + ($day_of_month + 1);
                if ($next->day_of_month > $pos_day) {

                    # we'll roll to next month, so...
                    my $next_month = $next;
                    while ($next_month->mon == $next->mon) {
                        $next_month += ONE_DAY;
                    }
                    my $next_last_day =
                      $self->_last_day_of_month($next_month->mon, $next_month->year);
                    $pos_day = $next_last_day + ($day_of_month + 1);
                }
                $day_of_month = $pos_day;
            }

            if ($next->day_of_month > $day_of_month) {

                # never roll the clock back.  Roll to the next month.
                my $mon = $next->mon;
                while ($next->mon == $mon) {
                    $next += ONE_DAY;
                }
                $next += (($day_of_month - 1) * ONE_DAY);

            } elsif ($next->day_of_month < $day_of_month) {
                $next += (($day_of_month - $next->day_of_month) * ONE_DAY);
            }
        }

    } else {

        # we have an interval
        $next = Time::Piece->from_mysql_datetime($self->initial_date);
        while ($next < $now) {
            $next += ($day_interval * ONE_DAY);
        }
    }

    if ($skip_match && ($next == $now)) {
        $now += ONE_MINUTE;
        return $self->_calc_next_run(now => $now);
    }

    return $next->mysql_datetime;
}

sub _last_day_of_month {
    my $self = shift;
    my ($month, $year) = @_;

    my $t = Time::Piece->strptime("$month/1/$year 12", "%m/%d/%Y %H");

    # add_months() not added until T::P 1.13, so we do it the long way
    while ($t->mon == $month) {
        $t += ONE_DAY;
    }
    $t -= ONE_DAY;    # take one back;

    return $t->day_of_month;
}

=item C<< $sched->delete >>

=item C<< Krang::Schedule->delete( $schedule_id ) >>

Removes the schedule from the database.  It will never run again.
This happens to repeat => C<never> schedules automatically after they
are run.

=cut

sub delete {
    my $self = shift;
    my $schedule_id = shift || $self->{schedule_id};

    my $query = "DELETE FROM schedule WHERE schedule_id = ?";
    my $dbh   = dbh();
    $dbh->do($query, undef, $schedule_id);

    if (ASSERT) {
        my $count = pkg('Schedule')->find(
            schedule_id => $schedule_id,
            count       => 1
        );
        assert($count == 0);
    }

    # return 1 by default for testing
    return 1;
}

=item @schedules = Krang::Schedule->find(...)

Finds schedules in the database based on supplied criteria.

Fields may be matched using SQL matching.  Appending "_like" to a field
name will specify a case-insensitive SQL match.

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

=item inactive

If set to 1, return only inactive schedules. Defaults to 0 (return
only active schedules).

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

=item select_for_update

Lock the found rows for update.

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my ($fields, @params, $where_clause);

    # grab ascend/descending, limit, and offset args
    my $ascend = delete $args{order_desc} ? 'DESC' : 'ASC';
    my $limit    = delete $args{limit}    || '';
    my $offset   = delete $args{offset}   || '';
    my $order_by = delete $args{order_by} || 'schedule_id';

    # set search fields
    my $count    = delete $args{count}    || '';
    my $ids_only = delete $args{ids_only} || '';

    # find only active schedules per default
    $args{inactive} = 0 unless defined($args{inactive});

    # select for update
    my $select_for_update = delete($args{select_for_update});

    # set bool to determine whether to use $row or %row for binding below
    my $single_column = $ids_only || $count ? 1 : 0;

    croak(  __PACKAGE__
          . "->find(): 'count' and 'ids_only' were supplied. "
          . "Only one can be present.")
      if ($count && $ids_only);

    # exclude 'element'
    $fields =
      $count
      ? 'count(*)'
      : ($ids_only ? 'schedule_id' : join(", ", map { "`$_`" } keys %schedule_cols));

    # set up WHERE clause and @params, croak unless the args are in
    # SCHEDULE_RO, SCHEDULE_RW or SCHEDULE_RW_NOTIFY.
    my @invalid_cols;
    for my $arg (keys %args) {
        my $like = 1 if $arg =~ /_like$/;
        (my $lookup_field = $arg) =~ s/^(.+)_like$/$1/;

        push @invalid_cols, $arg
          unless (exists $schedule_cols{$lookup_field} || $arg =~ /^next_run/);

        my $and = defined $where_clause && $where_clause ne '' ? ' AND' : '';
        if ($arg eq 'schedule_id' && ref $args{$arg} eq 'ARRAY') {
            my $tmp = join(" OR ", map { "schedule_id = ?" } @{$args{$arg}});
            $where_clause .= "$and ($tmp)";
            push @params, @{$args{$arg}};
        }

        # handle next_run date comparisons
        elsif ($arg =~ /^next_run_(.+)$/) {
            my @gtltargs = split(/_/, $1);

            croak("'$arg' is an invalid 'next_run' field comparison.")
              unless ($gtltargs[0] eq 'greater'
                || $gtltargs[0] eq 'less'
                || scalar @gtltargs == 1
                || scalar @gtltargs == 3);

            my $operator = $gtltargs[0] eq 'greater' ? '>' : '<';
            $operator .= '=' if scalar @gtltargs == 3;

            $where_clause .= "$and next_run $operator ";
            if ($args{$arg} eq 'now()') {
                $where_clause .= 'now()';
            } else {
                $where_clause .= '?';
                push @params, $args{$arg};
            }
        } else {
            if (not defined $args{$arg}) {
                $where_clause .= "$and `$lookup_field` IS NULL";
            } else {
                $where_clause .=
                  $like
                  ? "$and `$lookup_field` LIKE ?"
                  : "$and `$lookup_field` = ?";
                push @params, $args{$arg};
            }
        }
    }

    croak(
        "The following passed search parameters are invalid: '" . join("', '", @invalid_cols) . "'")
      if @invalid_cols;

    # construct base query
    my $query = "SELECT $fields FROM schedule";

    # add WHERE and ORDER BY clauses, if any
    $query .= " WHERE $where_clause"        if $where_clause;
    $query .= " ORDER BY $order_by $ascend" if $order_by;

    # add LIMIT clause, if any
    if ($limit) {
        $query .= $offset ? " LIMIT $offset, $limit" : " LIMIT $limit";
    } elsif ($offset) {
        $query .= " LIMIT $offset, 18446744073709551615";
    }

    # select for update
    if ($select_for_update) {
        $query .= ' for update';
    }

    # dbh connect options
    my @dbh_options = (no_cache => 1);
    push @dbh_options, (AutoCommit => 0) if $select_for_update;

    my $dbh = dbh(@dbh_options);
    my $sth = $dbh->prepare($query);

    debug(__PACKAGE__ . "->find() SQL: $query");
    debug(__PACKAGE__ . "->find() SQL ARGS: @params");

    while (1) {
        eval { $sth->execute(@params); };
        my $error = $@;
        last unless $error;
        # try again if we hit a deadlock
        if ($error =~ m/Deadlock found when trying to get lock; try restarting transaction/) {
            sleep 1;
            next;
        }
        die $error;
    }

    # holders for query results and new objects
    my ($row, @schedules);

    # bind fetch calls to $row or %$row
    # a possibly insane micro-optimization :)
    if ($single_column) {
        $sth->bind_col(1, \$row);
    } else {
        $sth->bind_columns(\(@$row{@{$sth->{NAME_lc}}}));
    }

    # construct category objects from results
    while ($sth->fetchrow_arrayref()) {

        # if we just want count or ids
        if ($single_column) {
            push @schedules, $row;
        } else {
            my $class = pkg('Schedule::Action::' . $row->{action});
            eval "use $class";

            if ($@) {
                croak "Error in find() method\n@_, $@";
            }

            push @schedules, bless({%$row}, $class);
        }
    }

    # thaw contexts, if necessary
    unless ($count or $ids_only) {
        for (@schedules) {

            # store frozen value in '_frozen_context'
            $_->{_frozen_context} = $_->{context};
            eval { $_->{context} = thaw($_->{context}) };
            croak(__PACKAGE__ . "->find(): Unable to thaw context: $@") if $@;
        }
    }

    # return number of rows if count, otherwise an array of ids or objects
    return $count ? $schedules[0] : @schedules;
}

=item C<< $sched->save >>

Saves the schedule to the database. It will now be run at its appointed
hour.

=cut

sub save {
    my $self        = shift;
    my $id          = $self->{schedule_id} || 0;
    my @save_fields = grep { $_ ne 'schedule_id' } keys %schedule_cols;
    my ($query);

    # validate 'repeat'
    croak(__PACKAGE__ . "->save(): 'repeat' field set to invalid setting - " . "$self->{repeat}")
      unless exists $repeat2seconds{$self->{repeat}};

    # freeze context in '_frozen_context'
    my $context = $self->{context};
    if ($context) {
        croak(__PACKAGE__ . "->save(): 'context' field is not an array ref")
          unless (ref $self->{context} && ref $self->{context} eq 'ARRAY');

        eval { $self->{_frozen_context} = nfreeze($context) };
        croak(__PACKAGE__ . "->save(): Unable to freeze context: $@") if $@;
    }

    # the object has already been saved once if $id
    if ($id) {
        $query =
            "UPDATE schedule SET "
          . join(", ", map { "`$_` = ?" } @save_fields)
          . " WHERE schedule_id = ?";
    } else {

        # build insert query
        $query =
            "INSERT INTO schedule ("
          . join(',', map { "`$_`" } @save_fields)
          . ") VALUES (?"
          . ", ?" x (scalar @save_fields - 1) . ")";
    }

    # bind parameters
    my @params =
      map { $context && $_ eq 'context' ? $self->{_frozen_context} : $self->{$_} } @save_fields;

    # need schedule_id for updates
    push @params, $id if $id;

    # croak if no rows are affected
    my $dbh = dbh();
    croak(  __PACKAGE__
          . "->save(): Unable to save Schedule object "
          . ($id ? "id '$id' " : '')
          . "to the DB.")
      unless $dbh->do($query, undef, @params);
    $self->{schedule_id} = $dbh->{mysql_insertid} unless $id;

    return $self;
}

=item $schedule->serialize_xml(writer => $writer, set => $set)

Serialize as XML. See L<Krang::DataSet> for details.

=cut

sub serialize_xml {
    my ($self,   %args) = @_;
    my ($writer, $set)  = @args{qw(writer set)};
    local $_;

    # open up <schedule> linked to schema/schedule.xsd
    $writer->startTag(
        'schedule',
        "xmlns:xsi"                     => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation" => 'schedule.xsd'
    );

    foreach ('schedule_id', 'object_type', 'object_id', 'action', 'repeat') {
        $writer->dataElement($_ => $self->{$_});
    }
    my $next_run = $self->{next_run} || '';
    $next_run =~ s/\s/T/;
    $writer->dataElement(next_run => $next_run);
    my $last_run = $self->{last_run} || '';
    $last_run =~ s/\s/T/;
    $writer->dataElement(last_run => $last_run) if $self->{last_run};
    my $initial_date = $self->{initial_date} || '';
    $initial_date =~ s/\s/T/;
    $writer->dataElement(initial_date => $initial_date);

    # an expiration date is optional
    my $expires = $self->{expires};
    if ($expires) {
        $expires =~ s/\s/T/;
        $writer->dataElement(expires => $expires);
    }

    $writer->dataElement(hour => $self->{hour}) if defined $self->{hour};
    $writer->dataElement(minute => $self->{minute})
      if defined $self->{minute};
    $writer->dataElement(day_of_week => $self->{day_of_week})
      if defined $self->{day_of_week};
    $writer->dataElement(day_of_month => $self->{day_of_month})
      if defined $self->{day_of_month};
    $writer->dataElement(day_interval => $self->{day_interval})
      if defined $self->{day_interval};

    foreach (
        'priority',          'inactive',          'failure_max_tries',
        'failure_delay_sec', 'failure_notify_id', 'success_notify_id'
      )
    {
        $writer->dataElement($_ => $self->{$_}) if defined($self->{$_});
    }

    # context
    if (my $context = $self->{context}) {
        my %c_hash = @$context;
        for my $key (keys %c_hash) {
            $writer->startTag('context');
            $writer->dataElement(key   => $key);
            $writer->dataElement(value => $c_hash{$key});
            $writer->endTag('context');

            $set->add(
                object => (pkg('User')->find(user_id => $c_hash{user_id}))[0],
                from   => $self
            ) if ($key eq 'user_id');
        }
    }

    # all done
    $writer->endTag('schedule');
}

=item C<< $schedule = Krang::Schedule->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML. See L<Krang::DataSet> for details.

If an incoming schedule has matching fields with an existing schedule,
it is ignored (not duplicated).

Note that last_run is not imported, next_run is translated to 'date'.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set)  = @args{qw(xml set)};

    # divide FIELDS into simple and complex groups
    my (%complex, %simple);

    # strip out all fields we don't want updated or used.
    @complex{qw(schedule_id object_id last_run context next_run initial_date expires)} = ();
    %simple =
      map { ($_, 1) }
      grep { not exists $complex{$_} } (SCHEDULE_RO, SCHEDULE_RW, SCHEDULE_RW_NOTIFY);

    # parse it up
    my $data = pkg('XML')->simple(
        xml           => $xml,
        suppressempty => 1
    );

    my $new_id = 0;
    if ($data->{object_id}) {
        $new_id = $set->map_id(
            class => pkg(ucfirst($data->{object_type})),
            id    => $data->{object_id}
        );
    }

    my $initial_date = $data->{initial_date};
    $initial_date =~ s/T/ /;
    my $expires = $data->{expires};
    $expires =~ s/T/ / if $expires;

    my %search_params = (
        object_type  => $data->{object_type},
        object_id    => $new_id,
        action       => $data->{action},
        repeat       => $data->{repeat},
        initial_date => $initial_date
    );

    $initial_date = Time::Piece->from_mysql_datetime($initial_date);
    $search_params{hour}         = $data->{hour}         if $data->{hour};
    $search_params{minute}       = $data->{minute}       if $data->{minute};
    $search_params{day_of_week}  = $data->{day_of_week}  if $data->{day_of_week};
    $search_params{day_of_month} = $data->{day_of_month} if $data->{day_of_month};
    $search_params{day_interval} = $data->{day_interval} if $data->{day_interval};

    debug(  __PACKAGE__
          . "->deserialize_xml() : finding schedules with params- "
          . join(',', (map { $search_params{$_} } keys %search_params)));

    # is there an existing object?
    my $schedule = (pkg('Schedule')->find(%search_params))[0] || '';

    if (not $schedule) {
        $schedule = pkg('Schedule')->new(
            object_id => $new_id,
            date      => $initial_date,
            (
                map { ($_, $data->{$_}) }
                  keys %simple
            )
        );
        $schedule->save;
    }

    return $schedule;
}

=item C<< pkg('Schedule')->activate(object_type => $type, object_id => $id) >>

Activate any schedules on object $type having id $id.

=cut

sub activate {
    shift->_toggle_inactive_flag(@_, action => 'activate');
}

=item C<< pkg('Schedule')->inactivate(object_type => $type, object_id => $id) >>

Inactivate any schedules on object $type having id $id.

=cut

sub inactivate {
    shift->_toggle_inactive_flag(@_, action => 'inactivate');
}

sub _toggle_inactive_flag {
    my ($self, %args) = @_;

    croak(__PACKAGE__ . "::$args{action}(): Missing argument '$_'")
      if grep { not $args{$_} } qw(object_type object_id action);

    my $flag = $args{action} eq 'activate' ? 0 : 1;

    my $dbh = dbh();

    my $query = <<SQL;
UPDATE schedule SET inactive = ?
WHERE  object_type = ?
AND    object_id   = ?
SQL

    debug(__PACKAGE__ . "->find() SQL: $query");

    $dbh->do($query, undef, $flag, $args{object_type}, $args{object_id})
      or croak(__PACKAGE__ . "->find() Unable to $args{action} Schedule object via SQL $query");

    return $self;
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

#
# check to confirm that the object associated with the schedule job still exists.
# if so, save it in $self->{object}.
#
# return 1 if the object exists.
# return 0 if the object does not exist.
#

sub _object_exists {
    my $self = shift;

    my $object;

    if ($self->{action} eq 'send') {
        my $alert = (pkg('Alert')->find(alert_id => $self->object_id))[0];
        return 1 if $alert;
    } else {
        my $type    = $self->object_type();
        my $id      = $self->object_id();
        my %context = defined($self->{context}) ? @{$self->{context}} : ();

        if ($type eq 'media') {
            ($object) = pkg('Media')->find(media_id => $id, %context);
        } elsif ($type eq 'story') {
            ($object) = pkg('Story')->find(story_id => $id, %context);
        } else {
            my $msg = sprintf("%s: unknown object type '%s'", __PACKAGE__, $type);
            die $msg;
        }
    }

    if ($object) {
        $self->{object} = $object;
        return 1;
    }

    return 0;

}

#
# _object_checked_out
#
# confirms that the object associated with the job is not checked out.
#
# returns 0 if the object is not checked out (or doesn't need to be).
# returns 1 if the object is checked out, or otherwise inaccessible.
#

sub _object_checked_out {

    my $self = shift;

    my $object;

    if ($self->{object}) {
        $object = $self->{object};
    } else {

        # might not have been found yet.
        if ($self->_object_exists) {
            $object = $self->{object};
        } else {
            return 0;
        }
    }

    # return checked_out status if possible.
    if ($object->can('checked_out')) {
        return $object->checked_out;
    }

    # not an issue if the object cannot be checked out.
    return 0;

}

#
# _allowable_object_types
#
# Returns a hash of allowable object types that actions can be scheduled for.
#

sub _allowable_object_types {
    my $self = shift;

    my @types = qw(alert media story tmp session analyze admin rate_limit);
    return map { $_ => 1 } @types;
}

=back

=cut

"JAPH";

