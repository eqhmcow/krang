package Krang::Schedule;

=head1 NAME

Krang::Schedule - manage scheduled events in Krang

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


  # save the schedule to the database
  $sched->save();

  # get the ID for a schedule
  $schedule_id = $schedule->schedule_id;

  # setup a weekly story publish
  $sched = Krang::Schedule->new(object_type => 'story',
                                object_id   => $story_id,
                                action      => 'publish',
                                repeat      => 'weekly',
                                day_of_week => 1,
                                hour        => 12,
                                minute      => 0);

  # setup a daily story publish
  $sched = Krang::Schedule->new(object_type => 'story',
                                object_id   => $story_id,
                                action      => 'publish',
                                repeat      => 'daily',
                                hour        => 12,
                                minute      => 0);

  # setup an hourly story publish
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

  # execute pending scheduled actions
  Krang::Schedule->run();

=head1 DESCRIPTION

This module is responsible for handling scheduled activities for
Krang.  Stories and Media have user-editable publishing and expiration
schedules.  Events which are attached to alerts may trigger
mail-sending scheduled jobs.

=cut


#
# Pragmas/Module Dependencies
##############################
# Pragmas
##########
use strict;
use warnings;

# External Modules
###################
use Carp qw(verbose croak);
use Exception::Class
  (Krang::Schedule::Duplicate => {fields => 'schedule_id'});
use Time::Piece;
use Time::Piece::MySQL;
use Time::Seconds;

# Internal Modules
###################
use Krang::DB qw(dbh);
use Krang::Media;
use Krang::Story;
use Krang::Template;

#
# Package Variables
####################
# Constants
############
# Read-only fields
use constant SCHEDULE_RO => qw(last_run
			       next_run
			       schedule_id);

# Read-write fields
use constant SCHEDULE_RW => qw(action
			       context
			       object_id
			       object_type
			       repeat);


# Globals
##########
our %action_map = (media => {expire => '',
                             mail => '',
                             publish => ''},
                   story => {expire => '',
                             mail => '',
                             publish => ''},
                   user => {expire => '',
                            mail => '',
                            publish => ''},);

# Lexicals
###########
my %repeat2seconds = (daily => ONE_DAY,
                      hourly => ONE_HOUR,
                      weekly => ONE_WEEK,
                      never => '');
my %schedule_args = map {$_ => 1}
  qw/action date day_of_week hour minute object_id object_type repeat/;
my %schedule_cols = map {$_ => 1} SCHEDULE_RO, SCHEDULE_RW;

# Constructor/Accessor/Mutator setup
use Krang::MethodMaker	new_with_init => 'new',
			new_hash_init => 'hash_init',
			get => [SCHEDULE_RO],
			get_set => [SCHEDULE_RW];


=head1 INTERFACE

=over

=item C<< $sched = Krang::Schedule->new() >>

Create a new schedule object.  The following keys are required:

=over

=item C<action>

The action to be performed.  Must be 'publish', 'expire' or 'mail'.

=item C<object_type>

The type of object which the action refers to.  Currently 'story',
'media' or 'user'.

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

=back

=cut

sub init {
    my $self = shift;
    my %args = @_;
    my (@bad_args, $repeat);
    my ($date, $day_of_week, $hour, $minute) = map {delete $args{$_}}
      qw/date day_of_week hour minute/;

    for (keys %args) {
        push @bad_args, $_ unless exists $schedule_args{$_};
    }
    croak(__PACKAGE__ . "->init(): The following constructor args are " .
          "invalid: '" . join("', '", @bad_args) . "'") if @bad_args;

    for (qw/action object_id object_type repeat/) {
        croak(__PACKAGE__ . "->init(): Required argument '$_' not present.")
          unless exists $args{$_};

        # conditionally required args
        if ($_ eq 'repeat') {
            $repeat = $args{$_};
            croak(__PACKAGE__ . "->init(): invalid value for 'repeat' field.")
              unless exists $repeat2seconds{$repeat};
            unless ($repeat eq 'never') {
                croak("'minute' argument required for hourly, daily, and " .
                      "weekly tasks.")
                  unless $minute;
                croak("'hour' argument required for daily and weekly tasks")
                  unless ($repeat eq 'hourly' || $hour);
                croak("'day_of_week' required for weekly tasks.")
                  if ($repeat eq 'weekly' && !$day_of_week);
              } else {
                  croak("'date' argument required for non-repetitive " .
                        "Schedule objects")
                    unless $date;
                  croak("'date' argument must be a Time::Piece object.")
                    unless ref $date && $date->isa('Time::Piece');
                  $date = $date->mysql_datetime;
            }
        }
    }

    $self->hash_init(%args);

    # calculate next run
    my $now = localtime;
    $self->{next_run} = $repeat eq 'never' ? $date :
      _next_run($now, $repeat, $day_of_week, $hour, $minute);

    return $self;
}


sub _next_run {
    my ($now, $repeat, $day_of_week, $hour, $minute) = @_;
    my $next = localtime;
    my $same_day = my $same_hour = my $same_week = 0;

# I
    if ($repeat eq 'weekly') {
# I.A
        if ($now->day_of_week > $day_of_week) {
            $next += ONE_WEEK - (($now->day_of_week - $day_of_week) * ONE_DAY);
            $next -= 3600;
# I.B
        } elsif ($day_of_week > $now->day_of_week) {
            $next += ($day_of_week - $now->day_of_week) * ONE_DAY;
# I.C
        } else {
            $same_week = 1;
        }

# I.D
        if ($now->hour > $hour) {
# I.D.i
            if ($same_week) {
                $next += ONE_WEEK - (($now->hour - $hour) * ONE_HOUR);
                $next -= 3600;
# I.D.ii
            } else {
                $next += ($hour - $now->hour) * ONE_HOUR;
            }
# I.E
        } elsif ($hour > $now->hour) {
            $next += ($hour - $now->hour) * ONE_HOUR;
# I.F
        } else {
            $same_hour = 1;
        }

# I.G
        if ($now->minute > $minute) {
# I.G.i
            if ($same_hour) {
                $next += ONE_WEEK - (($now->minute - $minute) * ONE_MINUTE);
# I.G.ii
            } else {
                $next += ($minute - $now->minute) * ONE_MINUTE;
            }
# I.H
        } elsif ($minute > $now->minute) {
            $next += ($minute - $now->minute) * ONE_MINUTE;
        }

# II
    } elsif ($repeat eq 'daily') {
# II.A
        if ($now->hour > $hour) {
            $next += ONE_DAY - (($now->hour - $hour) * ONE_HOUR);
# II.B
        } elsif ($hour > $now->hour) {
            $next += ($hour - $now->hour) * ONE_HOUR;
# II.C
        } else {
            $same_day = 1;
        }

# II.D
        if ($now->minute > $minute) {
# II.D.i
            if ($same_day) {
                $next += ONE_DAY - (($now->minute - $minute) * ONE_MINUTE);
# II.D.ii
            } else {
                $next += ($minute - $now->minute) * ONE_MINUTE;
            }
# II.E
        } elsif ($minute > $now->minute) {
            $next += ($minute - $now->minute) * ONE_MINUTE;
        }

# III
    } elsif ($repeat eq 'hourly') {
# III.A
        if ($now->minute > $minute) {
            $next += ONE_HOUR - (($now->minute - $minute) * ONE_MINUTE);
# III.B
        } elsif ($minute > $now->minute) {
            $next += ($minute - $now->minute) * ONE_MINUTE;
        }
    }

    return $next->mysql_datetime;
}


=item C<< $sched->delete >>

Removes the schedule from the database.  It will never run again.
This happens to repeat => 'never' schedules automatically after they
are run.

=cut

sub delete {
}


=item C<< $sched->duplicate_check >>

This method is called by save() to determine whether a successful save will
result in two duplicate Schedule objects.  If a duplicate is found a
Krang::Schedule::Duplicate exception is thrown.  The 'schedule_id' field
of the exception indicates the Schedule object the would have been duplicated.

=cut

sub duplicate_check {
    my $self = shift;
    my $id = $self->{schedule_id} || 0;
    my $dbh = dbh();
    my @params = map {$self->{$_}} qw/action object_id object_type repeat/;
    my $query = <<QUERY;
SELECT id
FROM schedule
WHERE action = ? AND object_id = ? AND object_type = ? AND repeat = ?
QUERY


    my ($schedule_id) = $dbh->selectrow_array($query, undef, @params) || 0;
    Krang::Schedule::Duplicate->throw(message => 'Duplicate Schedule exists.',
                                      schedule_id => $schedule_id)
        if $schedule_id;

    return $schedule_id;
}


=item @schedules = Krang::Schedule->find(...)

Finds schedules in the database based on supplied criteria.

Fields may be matched using SQL matching.  Appending "_like" to a
field name will specify a case-insensitive SQL match.

Available search options are:

=over

=item action

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
      ($ids_only ? 'schedule_id' : join(", ", grep {$_ ne 'element'}
                                        keys %schedule_cols));

    # set up WHERE clause and @params, croak unless the args are in
    # SCHEDULE_RO or SCHEDULE_RW
    my @invalid_cols;
    for my $arg (keys %args) {
        # don't use element
        next if $arg eq 'element';

        my $like = 1 if $arg =~ /_like$/;
        ( my $lookup_field = $arg ) =~ s/^(.+)_like$/$1/;

        push @invalid_cols, $arg unless exists $schedule_cols{$lookup_field};

        if ($arg eq 'schedule_id' && ref $args{$arg} eq 'ARRAY') {
            my $tmp = join(" OR ", map {"schedule_id = ?"} @{$args{$arg}});
            $where_clause .= " ($tmp)";
            push @params, @{$args{$arg}};
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

    # finish statement handle
    $sth->finish();

    # return number of rows if count, otherwise an array of ids or objects
    return $count ? $schedules[0] : @schedules;
}


=item C<< Krang::Schedule->run >>

This method runs all pending schedules.  It works by pulling a list of
schedules with next_run greater than current time.  It runs these
tasks and then updates their next_run according to their repeating
schedule.

Non-repeating tasks are deleted after they are run.  Hourly tasks get
next_run = next_run + 60 minutes.  Daily tasks get next_run = next_run
+ 1 day.  Weekly tasks get next_run = next_run + 1 week.

* N.B. - if the repeat field for a given object is set to 'never' the object
will be deleted after its action is performed.

=cut

sub run {
    my @objs = Krang::Schedule->find(next_run => "<= now()");

    for my $obj(@objs) {
        my ($action, $context, $schedule_id, $object_id, $type, $repeat) =
          map {$obj->{$_}}
            qw/action context schedule_id object_id object_type repeat/;

        # how do we handle context?  thaw it and pass it to the call
        # we're about to make
        my @args;
        eval {@args = thaw($context)};
        critical("Error thawing 'context' for Krang::Schedule " .
                 "'$schedule_id': $@")
          if $@;

        # what do we do in case of a failure
        my $call = $action_map{$type}->{$action};
        eval {&$call($object_id, @args)};
        critical("'$action' for Krang::$type id '$object_id' failed: $@")
          if $@;

        if ($repeat eq 'never') {
            $obj->delete();
        } else {
            my $now = localtime();
            my $next = Time::Piece->from_mysql_date_time($obj->{next_run}) +
              $repeat2seconds{$repeat};
            $obj->{last_run} = $now->mysql_datetime;
            $obj->{next_run} = $next->mysql_datetime;
            $obj->save();
        }
    }
}


=item C<< $sched->save >>

Saves the schedule to the database.  It will now be run at its
appointed hour.

=cut

sub save {
    my $self = shift;
    my $id = $self->{schedule_id} || 0;
    my @save_fields = grep {$_ ne 'schedule_id'} keys %schedule_cols;
    my $query;

    # validate 'repeat' and date settings

    # the object has already been saved once if $id
    if ($id) {
        $query = "UPDATE schedule SET " .
          join(", ", map {"$_ = ?"} @save_fields) .
            " WHERE user_id = ?";
    } else {
        # build insert query
        $query = "INSERT INTO schedule (" . join(',', @save_fields) .
          ") VALUES (?" . ", ?" x (scalar @save_fields - 1) . ")";
    }

    # bind parameters
    my @params = map {$self->{$_}} @save_fields;

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


=back

=head1 TO DO

=head1 SEE ALSO

=cut


my $quip = <<END;
1
END
