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
use Storable qw/freeze thaw/;
use Time::Piece;
use Time::Piece::MySQL;
use Time::Seconds;


# Internal Modules
###################
use Krang::DB qw(dbh);
use Krang::Log qw/ASSERT assert/;
use Krang::Media;
use Krang::Story;
use Krang::Template;

#
# Package Variables
####################
# Constants
############
# Debugging constant
use constant SCH_DEBUG => $ENV{SCH_DEBUG} || 0;

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
our %action_map = (alert => {send => sub { Krang::Alert->send(@_) } },
                   media => {expire => '',
                             publish => ''},
                   story => {expire => '',
                             publish => ''},
                   user => {expire => ''});

# Lexicals
###########
my %repeat2seconds = (daily => ONE_DAY,
                      hourly => ONE_HOUR,
                      weekly => ONE_WEEK,
                      never => '');
my %schedule_args = map {$_ => 1} SCHEDULE_RW,
  qw/date day_of_week hour minute/;
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

The action to be performed.  Must be 'publish', 'expire' or 'alert'.

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
                  unless defined $minute;
                croak("'hour' argument required for daily and weekly tasks")
                  unless ($repeat eq 'hourly' || defined $hour);
                croak("'day_of_week' required for weekly tasks.")
                  if ($repeat eq 'weekly' && not defined $day_of_week);
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


# The all-important date calculating sub..
# It returns a datetime to be stored in the object's next_run field
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


=item @schedules = Krang::Schedule->find(...)

Finds schedules in the database based on supplied criteria.

Fields may be matched using SQL matching.  Appending "_like" to a
field name will specify a case-insensitive SQL match.

Available search options are:

=over

=item action

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
    # SCHEDULE_RO or SCHEDULE_RW
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


=item C<< @schedule_ids_run = Krang::Schedule->run( $log_handle ) >>

=item C<< $object_run_count = Krang::Schedule->run( $log_handle ) >>

This method runs all pending schedules.  It works by pulling a list of
schedules with next_run greater than current time.  It runs these
tasks and then updates their next_run according to their repeating
schedule.

Non-repeating tasks are deleted after they are run.  Hourly tasks get
next_run = next_run + 60 minutes.  Daily tasks get next_run = next_run
+ 1 day.  Weekly tasks get next_run = next_run + 1 week.

The method returns an array of the ids that have run succesfully in list
context and a count of those ids in a scalar context.

* N.B. - if the repeat field for a given object is set to 'never' the object
will be deleted after its action is performed.

=cut

sub run {
    my ($self, $log) = @_;
    croak(__PACKAGE__ . "->run(): \$log handle is undefined or not an " .
          "IO::File object.")
      unless (defined $log || ref $log || $log->isa('IO::File'));
    my $now = localtime();
    my @objs = Krang::Schedule->find(next_run_less_or_equal => 'now()');
    my @schedule_ids_run;

    for my $obj(@objs) {
        my $eval_err;
        my ($action, $context, $schedule_id, $object_id, $type, $repeat) =
          map {$obj->{$_}}
            qw/action context schedule_id object_id object_type repeat/;

        # how do we handle context?  thaw it and pass it to the call
        # we're about to make
        my $args;
        if ($context) {
            eval {$args = thaw($context)};
            $eval_err = $@;
            $log->print("ERROR: can't thaw 'context' for Krang::Schedule " .
                        "'$schedule_id': $eval_err")
              if $eval_err;
        }

        # what do we do in case of a failure
        if (SCH_DEBUG) {
            $log->print("[$now] Schedule object id '$obj->{schedule_id}' " .
                        "did something.\n");
            if ($context) {
                require Data::Dumper;
                $log->print("Object should have run with the following " .
                            "context: " .
                            Data::Dumper->Dump([$context],['context']) .
                            "\n");
            }
        } else {
            my $call = $action_map{$type}->{$action};
            eval {
                if ($args) {
                    $call->($type.'_id' => $object_id, @$args );
                } else {
                    $call->($type.'_id' => $object_id);
                }
            };
            $eval_err = $@;
            $log->print("ERROR: '$action' for Krang::$type id '$object_id' " .
                        "failed: $eval_err")
              if $eval_err;
        }

        # we're assuming the action was successful unless we've gotten an
        # EVAL_ERR
        push @schedule_ids_run, $obj->{schedule_id} unless $eval_err;

        if ($repeat eq 'never') {
            $obj->delete();
        } else {
            my $next = Time::Piece->from_mysql_datetime($obj->{next_run}) +
              $repeat2seconds{$repeat};
            $obj->{last_run} = $now->mysql_datetime;
            $obj->{next_run} = $next->mysql_datetime;
            $obj->save();
        }
    }

    return wantarray ? @schedule_ids_run : scalar @schedule_ids_run;
}


=item C<< $sched->save >>

Saves the schedule to the database.  It will now be run at its
appointed hour.

=cut

sub save {
    my $self = shift;
    my $id = $self->{schedule_id} || 0;
    my @save_fields = grep {$_ ne 'schedule_id'} keys %schedule_cols;
    my $context_flag = exists $self->{context} ? 1 : 0;
    my ($context, $query);

    # validate 'repeat'
    croak(__PACKAGE__ . "->save(): 'repeat' field set to invalid setting - " .
          "$self->{repeat}")
      unless exists $repeat2seconds{$self->{repeat}};

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

    # if we have a context, preserve in $context and serialize it for storage
    if ($context_flag) {
        $context = $self->{context};
        eval {$self->{context} = freeze($self->{context})};
        croak(__PACKAGE__ . "->save(): Unable to serialize context: $@")
          if $@;
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

    # restore context
    $self->{context} = $context if $context_flag;

    return $self;
}


=back

=head1 TO DO

Action mappings need to be defined and then tested.

=cut


my $quip = <<QUIP;
1
QUIP
