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

  # N.B - $date must be a Time::Piece object see POD for new() method


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

  # remove files from temp older than 'max_age' (in hours)
  Krang::Schedule->clean_tmp(max_age => 24);

  # expire sessions older than 'max_age' param
  Krang::Schedule->expire_sessions(max_age => 12);

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
use File::Spec::Functions qw(catdir catfile);
use File::Path qw(rmtree);
use Storable qw/freeze thaw/;
use Time::Piece;
use Time::Piece::MySQL;
use Time::Seconds;


# Internal Modules
###################
use Krang::Conf qw(KrangRoot);
use Krang::DB qw(dbh);
use Krang::Log qw/ASSERT assert critical debug info/;
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
                               initial_date
			       schedule_id);

# Read-write fields
use constant SCHEDULE_RW => qw(action
			       context
			       object_id
			       object_type
			       repeat
                               day_of_week
                               hour
                               minute);


# Globals
##########
our %action_map = (alert => {send => sub { Krang::Alert->send(@_) } },
                   media => {expire  => sub {},
                             publish => sub {}},
                   story => {expire  => sub {},
                             publish => sub {}}
                   );

# Lexicals
###########
my %repeat2seconds = (daily => ONE_DAY,
                      hourly => ONE_HOUR,
                      weekly => ONE_WEEK,
                      never => '');
my %schedule_args = map {$_ => 1} SCHEDULE_RW, qw/date/;
my %schedule_cols = map {$_ => 1} SCHEDULE_RO, SCHEDULE_RW;
my $tmp_path = catdir(KrangRoot, 'tmp');

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
'media'.

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
    my ($date, $day_of_week, $hour, $minute, $test_date) =
      map {$args{$_}} qw/date day_of_week hour minute test_date/;

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
        } elsif ($_ eq 'context') {
            my $context = $args{$_};
            croak("'context' must be an array reference.")
               unless (ref $context && ref $context eq 'ARRAY');

            # setup field for holding frozen value
            $self->{_frozen_context} = '';
        }
    }

    $self->hash_init(%args);

    # calculate next run
    my $now = SCH_DEBUG ? $test_date : localtime;
    $self->{next_run} = $repeat eq 'never' ? $date :
      _next_run($now, $repeat, $day_of_week, $hour, $minute);
    
    $self->{initial_date} = $self->{next_run};

    return $self;
}


# The all-important date calculating sub..
# It returns a datetime to be stored in the object's next_run field
sub _next_run {
    my ($now, $repeat, $day_of_week, $hour, $minute) = @_;
    my $next = $now;
    my $same_day = my $same_hour = my $same_week = 0;

# I
    if ($repeat eq 'weekly') {
# I.A
        if ($now->day_of_week > $day_of_week) {
            $next += ONE_WEEK - (($now->day_of_week - $day_of_week) * ONE_DAY);
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


=item C<< @deletions = Krang::Schedule->clean_tmp( max_age => $max_age_hrs ) >>

=item C<< @deletions = Krang::Schedule->clean_tmp() >>

Class method that will remove all files in $KRANG_ROOT/tmp older than
$max_age_in_hours.  If no parameter is passed file and directories older than
the krang.conf value TmpMaxAge will be removed.  This method will croak if it
is unable to delete a file or directory.  Returns a list of files and
directories deleted.

=cut

sub clean_tmp {
    my $self = shift;
    my %args = @_;
    my $max_age = exists $args{max_age} ? $args{max_age} : 24;
    my $date = localtime();
    $date = $date - ($max_age * ONE_HOUR); 
    my (@dirs, @files);

    # build a list of files to delete
    opendir(DIR, $tmp_path) || croak("Can't open tmpdir: $!");
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

    info("Files to be deleted:\n\t" . join("\n\t", @files) . "\n\n") if @files;
    info("Directories to be deleted:\n\t" . join("\n\t", @dirs) . "\n\n")
      if @dirs;

    # handle warnings generated by File::Path
    local $SIG{__WARN__} = sub {info($_[0]);};

    # list of files deleted
    my @deletions;

    # delete files
    for (@files) {
        unless (unlink $_) {
            critical("Unable to delete '$_': $!");
        } else {
            push @deletions, $_;
        }
    }

    # delete directories
    for my $dir(@dirs) {
        rmtree([$dir], 1, 1);
        if (-e $dir) {
            critical("Unable to delete '$dir'.");
        } else {
            push @deletions, $dir;
        }
    }

    return @deletions;
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


=item C<<@ids = Krang::Schedule->expire_sessions( max_age => $max_age_hrs )>>

=item C<<@ids = Krang::Schedule->expire_sessions()>>

Class method that deletes sessions from the sessions table whose
'last_modified' field contains a value less than 'now() - INTERVAL
$max_age_in_hours HOUR'.  Returns a list of the session ids that have been
expired.

=cut

sub expire_sessions {
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
        info("Deleted sessions with the following " .
             "IDs:\n\t" . join("\n\t", @ids) . "\n\n");

        return @ids;
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


=item C<< @schedule_ids_run = Krang::Schedule->run() >>

=item C<< $object_run_count = Krang::Schedule->run() >>

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
    my $self = shift;
    my $now = localtime();
    my @objs = Krang::Schedule->find(next_run_less_or_equal => 'now()');
    my @schedule_ids_run;

    for my $obj(@objs) {
        my $eval_err;
        my ($action, $context, $schedule_id, $object_id, $type, $repeat) =
          map {$obj->{$_}}
            qw/action context schedule_id object_id object_type repeat/;

        # what do we do in case of a failure
        if (SCH_DEBUG) {
            debug("Schedule object id '$obj->{schedule_id}' did something.\n");
            if ($context) {
                require Data::Dumper;
                debug("Object should have run with the following context: " .
                      Data::Dumper->Dump([$context],['context']) . "\n");
            }
        } else {
            my $call = $action_map{$type}->{$action};
            eval {
                if ($context) {
                    $call->($type.'_id' => $object_id, @$context );
                } else {
                    $call->($type.'_id' => $object_id);
                }
            };
            $eval_err = $@;
            critical("ERROR: '$action' for Krang::$type id '$object_id' " .
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
    $writer->dataElement( minute => $self->{minute} ) if defined $self->{minute};
    $writer->dataElement( day_of_week => $self->{day_of_week} ) if defined $self->{day_of_week};
    
    # context
    if (my $context = $self->{context}) {
        my %c_hash = @$context;
        for my $key (keys %c_hash ) {
            $writer->startTag('context');
            $writer->dataElement( key => $key );
            $writer->dataElement( value => $c_hash{$key} );
            $writer->endTag('context');
                                                                                     
            $set->add(object => ($Krang::User->find( user_id => $c_hash{user_id}))[0], from => $self) if ($key eq 'user_id');
            # $set->add(object => ($Krang::Alert->find( alert_id => $c_hash{alert_id}))[0], from => $self) if ($key eq 'alert_id');
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
    @complex{qw(schedule_id object_id last_run context next_run initial_date)} = ();
    %simple = map { ($_,1) } grep { not exists $complex{$_} } (SCHEDULE_RO,SCHEDULE_RW);

    # parse it up
    my $data = Krang::XML->simple(xml           => $xml,
                                  suppressempty => 1);
    
    my $new_id = $set->map_id(class => "Krang::".ucfirst($data->{object_type}), id => $data->{object_id});

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

    debug(__PACKAGE__."->deserialize_xml() : finding schedules with params- ".join(',', (map { $search_params{$_} } keys %search_params) ));

    # is there an existing object?
    my $schedule = (Krang::Schedule->find( %search_params ))[0] || '';

    if (not $schedule) {
        $schedule = Krang::Schedule->new(   object_id => $new_id,
                                            date => $initial_date,
                                            (map { ($_,$data->{$_}) } keys %simple));
        $schedule->save;
    }

    return $schedule;
}

=back

=head1 TO DO

Action mappings need to be defined and then tested.

=cut


my $poem = <<POEM;
This Is Just to Say

I have eaten
the plums
that were in
the icebox

and which
you were probably
saving
for breakfast

Forgive me
they were delicious
so sweet
and so cold
POEM
