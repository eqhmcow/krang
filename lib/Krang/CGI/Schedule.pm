package Krang::CGI::Schedule;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => qw(CGI);
use strict;
use warnings;

use Carp qw(croak);
use Time::Piece;
use Time::Piece::MySQL;
use Krang::ClassLoader 'Schedule';
use Krang::ClassLoader Message => qw(add_message add_alert);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Widget  => qw(time_chooser decode_time datetime_chooser decode_datetime);
use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader 'AddOn';
use Krang::ClassLoader Localization => qw(localize);

our %OBJECT_ACTION_LABELS;
our %ADMIN_ACTION_LABELS;
our %ALL_ACTION_LABELS;

BEGIN {
    ## Get ObjectSchedulerActionList items from addons.
    %OBJECT_ACTION_LABELS = (
        publish => 'Publish',
        expire  => 'Expire',
        retire  => 'Retire',
    );

    my @object_addons = pkg('AddOn')->find(condition => 'EnableObjectSchedulerActions');

    my %obj_actionlist =
      map { $_ => ucfirst($_) }
      map { $_->conf()->get('ObjectSchedulerActionList') } @object_addons;

    %OBJECT_ACTION_LABELS = (%OBJECT_ACTION_LABELS, %obj_actionlist);

    ## Get AdminSchedulerActionList items from addons.
    my @admin_addons = pkg('AddOn')->find(condition => 'EnableAdminSchedulerActions');

    %ADMIN_ACTION_LABELS = map {
        $_ => join(' ', (map { ucfirst($_) } split /_/, $_))
      }
      map {
        $_->conf()->get('AdminSchedulerActionList')
      } @admin_addons;

    ## get the whole shebang
    %ALL_ACTION_LABELS = (
        %ADMIN_ACTION_LABELS, %OBJECT_ACTION_LABELS,
        clean  => 'Clean',
        delete => 'Delete'
    );
}

=head1 NAME

Krang::CGI::Schedule - web interface to manage scheduling for stories and media.

=head1 SYNOPSIS
  
  use Krang::ClassLoader 'CGI::Schedule';
  my $app = pkg('CGI::Schedule')->new();
  $app->run();

=head1 DESCRIPTION

Krang::CGI::Schedule provides a user interface to add and delete
 scheduled actions for pkg('Media') and pkg('Story') objects, as well as external administrative scheduler addons.

=head1 INTERFACE

Following are descriptions of all the run-modes provided by
Krang::CGI::Schedule.

=cut

# setup runmodes
sub setup {
    my $self = shift;

    $self->start_mode('edit');

    $self->run_modes(
        [
            qw(
              edit
              edit_admin
              add
              add_admin
              add_simple
              delete
              list_all
              save_and_view
              )
        ]
    );

    $self->tmpl_path('Schedule/');
}

=over 

=item edit()

Displays the current schedule associated with the story/media object and
allow deletions and additions to the schedule. 

Invoked by the user clicking on 'Schedule' from the story/media edit
screen.  It is expected that the corresponding story/media object
exists in the session.

When the user clicks 'Return' they will be directed back to the edit 
screen of the media/story object.

The following parameters are used with this runmode:

=over 4

=item object_type

Must be 'media' or 'story' - specifies which object to look for in 
session.

=back

=cut

sub edit {
    my $self     = shift;
    my $invalid  = shift;
    my $query    = $self->query;
    my $template = $self->load_tmpl('edit.tmpl', associate => $query, loop_context_vars => 1);

    $template->param($invalid => 1) if $invalid;

    # load params
    my $object_type = $query->param('object_type')
      || croak("No object type was specified. Need 'story' or 'media'.");
    croak("Invalid object type - must be 'story' or 'media'")
      if (($object_type ne 'story') and ($object_type ne 'media'));

    $template->param(is_story => 1) if ($object_type eq 'story');
    $template->param(is_media => 1) if ($object_type eq 'media');
    $template->param(object_type => $object_type);
    my $schedule_type = $query->param('advanced_schedule') ? 'advanced' : 'simple';

    # Get media or story object from session -- or die() trying
    my $object = $self->get_object($object_type);
    my $object_id = ($object_type eq 'story') ? $object->story_id : $object->media_id;

    # populate read-only story/media metadata fields
    $template->param('id'         => $object_id);
    $template->param('story_type' => localize($object->element->display_name))
      if ($object_type eq 'story');
    $template->param('current_version'   => $object->version);
    $template->param('published_version' => $object->published_version);
    $template->param('url'               => $object->url);

    my $weekdays = $self->_get_weekdays();

    if ($schedule_type eq 'simple') {
        $template->param('simple' => 1);

        # setup date selector for publish
        $template->param(publish_selector =>
              datetime_chooser(name => 'publish_date', query => $query, nochoice => 1));

    } else {
        $template->param('advanced' => 1);

        $template->param(full_date_selector =>
              datetime_chooser(name => 'full_date', query => $query, nochoice => 1));

        $template->param(
            hourly_minute_selector => scalar $query->popup_menu(
                -name   => 'hourly_minute',
                -values => [0 .. 59]
            )
        );

        $template->param(daily_time_selector =>
              time_chooser(name => 'daily_time', query => $query, nochoice => 1));

        $template->param(
            weekly_day_selector => scalar $query->popup_menu(
                -name   => 'weekly_day',
                -values => [sort keys %$weekdays],
                -labels => $weekdays
            )
        );

        $template->param(weekly_time_selector =>
              time_chooser(name => 'weekly_time', query => $query, nochoice => 1));

        %OBJECT_ACTION_LABELS =
          map { $_ => localize($OBJECT_ACTION_LABELS{$_}) } keys %OBJECT_ACTION_LABELS;

        $template->param(
            action_selector => scalar $query->popup_menu(
                -name   => 'action',
                -values => [keys %OBJECT_ACTION_LABELS],
                -labels => \%OBJECT_ACTION_LABELS
            )
        );

    }

    my $all_versions = $object->all_versions;
    my %version_labels = map { $_ => $_ }[@$all_versions];
    $version_labels{0} = localize('Newest Version');

    $template->param(
        version_selector => scalar $query->popup_menu(
            -name    => 'version',
            -values  => [0, @$all_versions],
            -labels  => \%version_labels,
            -default => 0
        )
    );

    # get existing scheduled actions for object
    my @existing_schedule = $self->get_existing_schedule($object_type, $object_id);
    $template->param('existing_schedule_loop' => \@existing_schedule) if @existing_schedule;

    return $template->output;
}

=item edit_admin()

Displays the scheduler screen for administrative scheduler addons not tied to media or story objects.  Allows deletions and additions to the schedule.

Invoked by the user clicking on 'Schedule' from the admin section of the left nav bar. 
This feature provides general cron like functionality to the krang scheduler.

=back

=cut

sub edit_admin {
    my $self     = shift;
    my $invalid  = shift;
    my $query    = $self->query;
    my $template = $self->load_tmpl('edit_admin.tmpl', associate => $query);

    $template->param($invalid => 1) if $invalid;

    # populate read-only story/media metadata fields
    $template->param(
        full_date_selector => datetime_chooser(name => 'full_date', query => $query, nochoice => 1)
    );

    $template->param(
        hourly_minute_selector => scalar $query->popup_menu(
            -name   => 'hourly_minute',
            -values => [0 .. 59]
        )
    );

    $template->param(
        daily_time_selector => time_chooser(name => 'daily_time', query => $query, nochoice => 1));

    my $weekdays = $self->_get_weekdays();

    $template->param(
        weekly_day_selector => scalar $query->popup_menu(
            -name   => 'weekly_day',
            -values => [sort keys %$weekdays],
            -labels => $weekdays
        )
    );

    $template->param(
        weekly_time_selector => time_chooser(name => 'weekly_time', query => $query, nochoice => 1)
    );

    %ADMIN_ACTION_LABELS =
      map { $_ => localize($ADMIN_ACTION_LABELS{$_}) } keys %ADMIN_ACTION_LABELS;

    $template->param(
        action_selector => scalar $query->popup_menu(
            -name   => 'action',
            -values => [keys %ADMIN_ACTION_LABELS],
            -labels => \%ADMIN_ACTION_LABELS
        )
    );

    return $template->output;
}

# used by 'Jobs' admin tool
sub list_all {
    my $self  = shift;
    my $query = $self->query;

    my $template = $self->load_tmpl('list_all.tmpl', associate => $query);

    my $weekdays = $self->_get_weekdays();

    my $pager = pkg('HTMLPager')->new(
        cgi_query    => $query,
        persist_vars => {
            rm          => 'list_all',
            is_list_all => 1,
        },
        use_module    => pkg('Schedule'),
        columns       => [qw( asset schedule next_run action version checkbox_column )],
        column_labels => {
            asset    => 'Asset',
            schedule => 'Schedule',
            next_run => 'Next Run',
            action   => 'Action',
            version  => 'Version'
        },
        row_handler => sub { $self->list_all_row_handler(@_, $weekdays) },
        id_handler  => sub { return $_[0]->schedule_id },
    );

    # Run pager
    $template->param(
        pager_html => $pager->output(),
        row_count  => $pager->row_count
    );

    return $template->output;
}

sub list_all_row_handler {
    my ($self, $row, $schedule, $pager, $weekdays) = @_;

    $row->{asset} = localize(ucfirst($schedule->object_type)) . ' ' . $schedule->object_id;

    my %context = $schedule->context  ? @{$schedule->context} : ();
    my $version = $context{'version'} ? $context{'version'}   : '';
    my $frequency = ($schedule->repeat eq 'never') ? 'One Time' : ucfirst($schedule->repeat);
    my $s_params;

    my $localize = $self->_get_datetime_semantic();

    if ($frequency eq 'One Time') {
        $s_params =
          Time::Piece->from_mysql_datetime($schedule->next_run)
          ->strftime(localize('%m/%d/%Y %I:%M %p'));
    } elsif ($frequency eq 'Hourly') {
        ($schedule->minute eq '0')
          ? ($s_params = $localize->{'on the hour'})
          : ($s_params = $schedule->minute . " " . $localize->{"minutes past the hour"});
    } elsif ($frequency eq 'Daily') {
        my ($hour, $ampm) = convert_hour($schedule->hour);
        $s_params = "$hour:" . convert_minute($schedule->minute) . " $ampm";
    } elsif ($frequency eq 'Weekly') {
        my ($hour, $ampm) = convert_hour($schedule->hour);
        $s_params =
            $weekdays->{$schedule->day_of_week} . " "
          . $localize->{"at"}
          . " $hour:"
          . convert_minute($schedule->minute)
          . " $ampm";
    }

    $s_params =
        ($frequency eq 'Daily')
      ? ($localize->{$frequency} . " $localize->{at} " . $s_params)
      : ($localize->{$frequency} . ', ' . $s_params);

    $row->{schedule} = $s_params;
    $row->{next_run} =
      Time::Piece->from_mysql_datetime($schedule->next_run)
      ->strftime(localize('%m/%d/%Y %I:%M %p'));
    $row->{action} =
      $schedule->action ? localize($ALL_ACTION_LABELS{$schedule->action}) : localize('[n/a]');
    $row->{version} = $version ? $version : localize('[n/a]');
}

# Get the media or story object from session or die() trying
sub get_object {
    my ($self, $object_type) = @_;
    my $edit_uuid = $self->query->param('edit_uuid');

    # Get media or story object from session -- or die() trying
    my $object;
    if( $object_type eq 'story' ) {
        $object = $self->get_session_story_obj($edit_uuid);
    } elsif( $object_type eq 'media' ) {
        $object = $self->get_session_media_obj($edit_uuid);
    } else {
        $object = $session{$object_type};
    }
    die("No object available for schedule edit") unless $object && ref $object;

    return $object;
}

sub get_existing_schedule {
    my ($self, $object_type, $object_id) = @_;

    my @schedules = pkg('Schedule')->find('object_type' => $object_type, 'object_id' => $object_id);

    my @existing_schedule_loop = ();

    my $weekdays = $self->_get_weekdays();
    my $localize = $self->_get_datetime_semantic();

    foreach my $schedule (@schedules) {
        my %context = $schedule->context  ? @{$schedule->context} : ();
        my $version = $context{'version'} ? $context{'version'}   : '';
        my $frequency = ($schedule->repeat eq 'never') ? 'One Time' : ucfirst($schedule->repeat);
        my $s_params;

        if ($frequency eq 'One Time') {
            $s_params =
              Time::Piece->from_mysql_datetime($schedule->next_run)
              ->strftime(localize('%m/%d/%Y %I:%M %p'));
        } elsif ($frequency eq 'Hourly') {
            ($schedule->minute eq '0')
              ? ($s_params = $localize->{'on the hour'})
              : ($s_params = $schedule->minute . " $localize->{'minutes past the hour'}");
        } elsif ($frequency eq 'Daily') {
            my ($hour, $ampm) = convert_hour($schedule->hour);
            $s_params = "$hour:" . convert_minute($schedule->minute) . " $ampm";
        } elsif ($frequency eq 'Weekly') {
            my ($hour, $ampm) = convert_hour($schedule->hour);
            $s_params =
                $weekdays->{$schedule->day_of_week}
              . " $localize->{at} $hour:"
              . convert_minute($schedule->minute)
              . " $ampm";
        }

        $s_params =
            ($frequency eq 'Daily')
          ? ($localize->{$frequency} . " $localize->{at} " . $s_params)
          : ($localize->{$frequency} . ', ' . $s_params);

        push(
            @existing_schedule_loop,
            {
                'schedule_id' => $schedule->schedule_id,
                'schedule'    => $s_params,
                'next_run'    => Time::Piece->from_mysql_datetime($schedule->next_run)
                  ->strftime(localize('%m/%d/%Y %I:%M %p')),
                'action'  => localize($ALL_ACTION_LABELS{$schedule->action}),
                'version' => $version,
            }
        );
    }

    return @existing_schedule_loop;
}

sub convert_minute {
    my $minute = shift;
    $minute = "0" . $minute if ($minute <= 9);
    return $minute;
}

sub convert_hour {
    my $hour = shift;

    if (localize('AMPM') eq 'AMPM') {
        if ($hour >= 13) {
            return ($hour - 12), 'PM';
        } elsif ($hour == 12) {
            return $hour, 'PM';
        } elsif ($hour == 0) {
            return 12, 'AM';
        } else {
            return $hour, 'AM';
        }
    }
}

=over

=item add() 

Adds events to schedule based on UI selections

=back

=cut

sub add {
    my $self = shift;
    my $q    = $self->query();

    my $action  = $q->param('action');
    my $version = $q->param('version');
    my @context;
    push @context, (version => $version) if $version;

    my $object_type = $q->param('object_type');

    # Get media or story object from session -- or die() trying
    my $object = $self->get_object($object_type);
    my $object_id = ($object_type eq 'story') ? $object->story_id : $object->media_id;

    my $repeat = $q->param('repeat');
    unless ($repeat) {
        add_alert('no_date_type');
        return $self->edit('no_date_type');
    }

    $q->param("repeat_$repeat" => 1);

    my $schedule;

    if ($repeat eq 'never') {
        my $date = decode_datetime(name => 'full_date', query => $q);
        if (not $date) {
            add_alert('invalid_datetime');
            return $self->edit('invalid_datetime');
        }

        $schedule = pkg('Schedule')->new(
            object_type => $object_type,
            object_id   => $object_id,
            action      => $action,
            repeat      => 'never',
            context     => \@context,
            date        => $date
        );
    } elsif ($repeat eq 'hourly') {
        $schedule = pkg('Schedule')->new(
            object_type => $object_type,
            object_id   => $object_id,
            action      => $action,
            context     => \@context,
            repeat      => 'hourly',
            minute      => $q->param('hourly_minute')
        );
    } elsif ($repeat eq 'daily') {
        my ($hour, $minute) = decode_time(name => 'daily_time', query => $q);
        $minute = 0 if (!defined $minute);
        unless (defined $hour) {
            add_alert('no_hour');
            return $self->edit('no_hour');
        }

        $schedule = pkg('Schedule')->new(
            object_type => $object_type,
            object_id   => $object_id,
            action      => $action,
            context     => \@context,
            repeat      => 'daily',
            minute      => $minute,
            hour        => $hour
        );
    } elsif ($repeat eq 'weekly') {
        my ($hour, $minute) = decode_time(name => 'weekly_time', query => $q);
        $minute = 0 if (!defined $minute);
        unless (defined $hour) {
            add_alert('no_hour');
            return $self->edit('no_weekly_hour');
        }

        my $day = $q->param('weekly_day');

        $schedule = pkg('Schedule')->new(
            object_type => $object_type,
            object_id   => $object_id,
            action      => $action,
            repeat      => 'weekly',
            context     => \@context,
            day_of_week => $day,
            minute      => $minute,
            hour        => $hour
        );
    }

    $schedule->save();
    add_message('new_event');

    return $self->edit();
}

=over

=item add_admin() 

Adds events to admin scheduler based on UI selections

=back

=cut

sub add_admin {
    my $self = shift;
    my $q    = $self->query();

    my $action  = $q->param('action');
    my $version = $q->param('version');
    my @context;
    push @context, (version => $version) if $version;

    my $object_type = $q->param('object_type') || 'admin';

    my ($object, $object_id);

    # Get media or story object from session -- or die() trying

    if ($object_type ne 'admin') {
        $object = $self->get_object($object_type);
        $object_id = ($object_type eq 'story') ? $object->story_id : $object->media_id;
    }

    my $repeat = $q->param('repeat');
    unless ($repeat) {
        add_alert('no_date_type');
        return $self->edit_admin('no_date_type');
    }

    $q->param("repeat_$repeat" => 1);

    my $schedule;

    if ($repeat eq 'never') {
        my $date = decode_datetime(name => 'full_date', query => $q);
        if (not $date) {
            add_alert('invalid_datetime');
            return $self->edit_admin('invalid_datetime');
        }

        $schedule = pkg('Schedule')->new(
            object_type => $object_type,
            object_id   => $object_id,
            action      => $action,
            repeat      => 'never',
            context     => \@context,
            date        => $date
        );
    } elsif ($repeat eq 'hourly') {
        $schedule = pkg('Schedule')->new(
            object_type => $object_type,
            object_id   => $object_id,
            action      => $action,
            context     => \@context,
            repeat      => 'hourly',
            minute      => $q->param('hourly_minute')
        );
    } elsif ($repeat eq 'daily') {
        my ($hour, $minute) = decode_time(name => 'daily_time', query => $q);
        $minute = 0 if (!defined $minute);
        unless (defined $hour) {
            add_alert('no_hour');
            return $self->edit_admin('no_hour');
        }

        $schedule = pkg('Schedule')->new(
            object_type => $object_type,
            object_id   => $object_id,
            action      => $action,
            context     => \@context,
            repeat      => 'daily',
            minute      => $minute,
            hour        => $hour
        );
    } elsif ($repeat eq 'weekly') {
        my ($hour, $minute) = decode_time(name => 'weekly_time', query => $q);
        $minute = 0 if (!defined $minute);
        unless (defined $hour) {
            add_alert('no_hour');
            return $self->edit_admin('no_weekly_hour');
        }

        my $day = $q->param('weekly_day');

        $schedule = pkg('Schedule')->new(
            object_type => $object_type,
            object_id   => $object_id,
            action      => $action,
            repeat      => 'weekly',
            context     => \@context,
            day_of_week => $day,
            minute      => $minute,
            hour        => $hour
        );
    }

    $schedule->save();
    add_message('new_event');

    return $self->edit_admin();
}

=over

=item add_simple()

Adds simple scheduling (publish only) to schedule.

=back

=cut

sub add_simple {
    my $self    = shift;
    my $q       = $self->query();
    my $version = $q->param('version');
    my @context;
    push @context, (version => $version) if $version;

    my $date = decode_datetime(name => 'publish_date', query => $q);

    my $object_type = $q->param('object_type');

    # Get media or story object from session -- or die() trying
    my $object = $self->get_object($object_type);
    my $object_id = ($object_type eq 'story') ? $object->story_id : $object->media_id;

    if ($date) {
        my $schedule = pkg('Schedule')->new(
            object_type => $object_type,
            object_id   => $object_id,
            action      => 'publish',
            repeat      => 'never',
            context     => \@context,
            date        => $date
        );

        $schedule->save();

        add_message('scheduled_publish');
        return $self->edit();
    } else {
        add_alert('invalid_datetime');
        return $self->edit('invalid_datetime');
    }

}

=over

=item delete()

Delete selected schedules from the database by schedule_id.

=back

=cut

sub delete {
    my $self = shift;
    my $q    = $self->query();
    my @delete_list =
      $q->param('is_list_all')
      ? ($q->param('krang_pager_rows_checked'))
      : ($q->param('schedule_delete_list'));

    unless (@delete_list) {
        add_alert('missing_schedule_delete_list');
        return $q->param('is_list_all') ? $self->list_all : $self->edit();
    }

    foreach my $schedule_id (@delete_list) {
        pkg('Schedule')->delete($schedule_id);
    }

    add_message('deleted_selected');
    return $q->param('is_list_all') ? $self->list_all : $self->edit();
}

=over

=item save_and_view()

Preserve params and view version of story

=back

=cut

sub save_and_view {
    my $self = shift;
    my $q    = $self->query();

    $q->param('return_script' => 'schedule.pl');
    $q->param('return_params' => rm => $q->param('rm'));

    my $version = $q->param('version');
    $version ? ($version = '&version=' . $version) : ($version = '&version=');

    my $object_type = $q->param('object_type');
    $self->header_props(-uri => $object_type
          . '.pl?rm=view&return_script=schedule.pl&return_params=rm&return_params=edit&return_params=object_type&return_params='
          . $object_type
          . '&return_params=advanced_schedule&return_params='
          . $q->param('advanced_schedule')
          . $version);
    $self->header_type('redirect');
    return;

}

# localization helper methods
sub _get_weekdays {
    my $self = shift;

    my %weekdays = (
        0 => 'Sunday',
        1 => 'Monday',
        2 => 'Tuesday',
        3 => 'Wednesday',
        4 => 'Thursday',
        5 => 'Friday',
        6 => 'Saturday'
    );

    unless ($session{language} && $session{language} eq 'en') {
        @weekdays{0 .. 6} = localize('FULLDAY_LABELS');
    }

    return \%weekdays;
}

sub _get_datetime_semantic {
    my $self = shift;
    return {
        'One Time'              => localize('One Time'),
        Hourly                  => localize('Hourly'),
        Daily                   => localize('Daily'),
        Weekly                  => localize('Weekly'),
        at                      => localize('at'),
        'on the hour'           => localize('on the hour'),
        'minutes past the hour' => localize('minutes past the hour'),
    };
}

1;
