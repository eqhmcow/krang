package Krang::CGI::Schedule;
use base qw(Krang::CGI);
use strict;
use warnings;

use Carp qw(croak);
use Time::Piece;
use Time::Piece::MySQL;
use Krang::Schedule;
use Krang::Message qw(add_message);
use Krang::Session qw(%session);
use Krang::Log qw(debug);
use Krang::Widget qw(datetime_chooser decode_datetime);
use constant SCHEDULE_PROTOTYPE => {
                                    schedule_id => '',
                                    repeat => '',
                                    action => '',
                                    context => '',
                                    object_type => '',
                                    object_id => '',
                                    last_run => '',
                                    next_run => '' 
                                    };

our %ACTION_LABELS = (
                      publish  => 'Publish',
                      expire   => 'Expire',
                     );

our %WEEKDAYS = (
                    0 => 'Sunday',
                    1 => 'Monday',
                    2 => 'Tuesday',
                    3 => 'Wednesday',
                    4 => 'Thursday',
                    5 => 'Friday',
                    6 => 'Saturday'
                );

=head1 NAME

Krang::CGI::Schedule - web interface to manage scheduling for stories and media.

=head1 SYNOPSIS
  
  use Krang::CGI::Schedule;
  my $app = Krang::CGI::Schedule->new();
  $app->run();

=head1 DESCRIPTION

Krang::CGI::Schedule provides a user interface to add and delete
 scheduled actions for Krang::Media and Krang::Story objects.

=head1 INTERFACE

Following are descriptions of all the run-modes provided by
Krang::CGI::Schedule.

=cut

# setup runmodes
sub setup {
    my $self = shift;

    $self->start_mode('edit');
    
    $self->run_modes([qw(
                            edit
                            add
                            add_simple
                            delete
                    )]);

    $self->tmpl_path('Schedule/');    
}

=over 

=item edit

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
    my $self = shift;
    my $query = $self->query;
    my $template = $self->load_tmpl('edit.tmpl', associate => $query);

    # load params
    my $object_type = $query->param('object_type') || croak("No object type was specified. Need 'story' or 'media'.");
    croak("Invalid object type - must be 'story' or 'media'")
      if ( ($object_type ne 'story') and ($object_type ne 'media') );

    $template->param( is_story => 1 ) if ($object_type eq 'story');
    $template->param( is_media => 1 ) if ($object_type eq 'media');
    $template->param( object_type => $object_type );
    my $schedule_type = $query->param('advanced_schedule') ? 'advanced' : 'simple';
    # Get media or story object from session -- or die() trying
    my $object = $self->get_object($object_type);
    my $object_id = ($object_type eq 'story') ? $object->story_id  :  $object->media_id;
    
    # populate read-only story/media metadata fields
    $template->param( 'id' => $object_id );
    $template->param( 'story_type' => $object->element->display_name ) if ($object_type eq 'story');
    $template->param( 'current_version' => $object->version );
    $template->param( 'published_version' => $object->published_version );
    $template->param( 'url' => $object->url );

    if ($schedule_type eq 'simple') {
        $template->param( 'simple' => 1 );
                                                                                  
        # setup date selector for publish
        $template->param( publish_selector => datetime_chooser(name=>'publish_date', query=>$query, nochoice => 1));
       
        my %version_labels = map { $_ => $_ } [0 .. $object->version]; 
        $version_labels{0} = 'Newest Version';

        $template->param(version_selector => scalar
                         $query->popup_menu(-name    => 'version',
                                            -values  => [0 .. $object->version],
                                            -labels => \%version_labels,
                                            -default => 0));
                                                                                  
    } else {
        $template->param( 'advanced' => 1 );
    }

    # get existing scheduled actions for object
    my @existing_schedule = get_existing_schedule($object_type, $object_id);
    $template->param( 'existing_schedule_loop' => \@existing_schedule ) if @existing_schedule;

    return $template->output; 
}

# Get the media or story object from session or die() trying
sub get_object {
    my $self = shift;
    my $object_type = shift;                            
                                            
    # Get media or story object from session -- or die() trying
    my $object = $session{$object_type};
    die ("No story or media object available for schedule edit") unless (ref($object));
                                                                        
    return $object;
}

sub get_existing_schedule {
    my ($object_type, $object_id) = @_;
    my @schedules = Krang::Schedule->find( 'object_type' => $object_type, 'object_id' => $object_id );
    
    my @existing_schedule_loop = ();

    foreach my $schedule (@schedules) {
        my %context = $schedule->context ? @{$schedule->context} : ();
        my $version = $context{'version'} ? $context{'version'} : '';
        my $frequency = ($schedule->repeat eq 'never') ? 'One Time' : ucfirst($schedule->repeat);
        my $s_params;

        if ($frequency eq 'One Time') {
            $s_params = Time::Piece->from_mysql_datetime($schedule->next_run)->cdate;
        } elsif ($frequency eq 'Hourly') {
            ($schedule->minute eq '0') ? ($s_params = 'on the hour') : ($s_params = $schedule->minute." minutes past the hour"); 
        } elsif ($frequency eq 'Daily') {
            my ($hour, $ampm) = convert_hour($schedule->hour);
            $s_params = "$hour:".convert_minute($schedule->minute)." $ampm"; 
        } elsif ($frequency eq 'Weekly') {
            my ($hour, $ampm) = convert_hour($schedule->hour);
            $s_params = $WEEKDAYS{$schedule->day_of_week}." at $hour:".convert_minute($schedule->minute)." $ampm";        
        }
        
        $s_params = ($frequency eq 'Daily') ? ($frequency.' at '.$s_params) : ($frequency.', '.$s_params);
        
        push(@existing_schedule_loop, {
                                                'schedule_id' => $schedule->schedule_id,
                                                'schedule' => $s_params,
                                                'next_run' => Time::Piece->from_mysql_datetime($schedule->next_run)->cdate,
                                                'action' => $ACTION_LABELS{$schedule->action},
                                                'version' => $version
                                            });
    }

    return @existing_schedule_loop;
}

sub convert_minute {
    my $minute = shift;
    $minute = "0".$minute if ($minute <= 9);
    return $minute;
}

sub convert_hour {
    my $hour = shift;

    if ($hour >= 13) {
        return ($hour - 12), 'PM'; 
    } elsif ($hour == 0) {
        return 12, 'AM';
    } else {
        return $hour, 'AM'; 
    }
}

=item add_simple()

Adds simple scheduling (publish only) to schedule.

=cut

sub add_simple {
    my $self = shift;
    my $q = $self->query();

    my $date = decode_datetime(name=>'publish_date', query=>$q);

    my $object_type = $q->param('object_type');

    # Get media or story object from session -- or die() trying
    my $object = $self->get_object($object_type);
    my $object_id = ($object_type eq 'story') ? $object->story_id  :  $object->media_id;
   
    if ($date) { 
        my $schedule;
        if ($q->param('version')) {
            $schedule = Krang::Schedule->new(   object_type => $object_type,
                                                object_id => $object_id,
                                                action => 'publish',
                                                repeat => 'never',
                                                context => [ version => $q->param('version') ],
                                                date => $date );
        } else {
            $schedule = Krang::Schedule->new(   object_type => $object_type,
                                                object_id => $object_id,
                                                action => 'publish',
                                                repeat => 'never',
                                                date => $date );
        }
 
        $schedule->save();
   
        add_message('scheduled_publish');
    } else {
        add_message('invalid_datetime');
    }

    return $self->edit(); 
}

=item delete()

Delete selected schedules from the database by schedule_id.

=cut

sub delete {
    my $self = shift;
    my $q = $self->query();
    my @delete_list = ( $q->param('schedule_delete_list') );

    unless (@delete_list) {
        add_message('missing_schedule_delete_list');
        return $self->edit();
    }

    foreach my $schedule_id (@delete_list) {
        Krang::Schedule->delete($schedule_id);
    } 
    
    add_message('deleted_selected');
    return $self->edit();      
}

=back

=cut

1;
