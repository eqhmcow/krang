package Krang::Schedule;
use strict;
use warnings;

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
'weekly' tasks.

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

=item C<< $sched->save >>

Saves the schedule to the database.  It will now be run at its
appointed hour.

=item C<< $sched->delete >>

Removes the schedule from the database.  It will never run again.
This happens to repeat => 'never' schedules automatically after they
are run.

=item @schedules = Krang::Schedule->find(...)

Finds schedules in the database based on supplied criteria.  

Fields may be matched using SQL matching.  Appending "_like" to a
field name will specify a case-insensitive SQL match.  

Available search options are:

=over

=item schedule_id

=item object_type

=item object_id

=item action

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

=item C<< Krang::Schedule->run >>

This method runs all pending schedules.  It works by pulling a list of
schedules with next_run greater than current time.  It runs these
tasks and then updates their next_run according to their repeating
schedule.  

Non-repeating tasks are deleted after they are run.  Hourly tasks get
next_run = next_run + 60 minutes.  Daily tasks get next_run = next_run
+ 1 day.  Weekly tasks get next_run = next_run + 1 week.

=back

=cut

1;
