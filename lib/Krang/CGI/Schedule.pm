package Krang::CGI::Schedule;
use base qw(Krang::CGI);
use strict;
use warnings;

use Carp qw(croak);
use Krang::Schedule;
use Krang::Message qw(add_message);
use Krang::Session qw(%session);
use Krang::Log qw(debug);

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

=head1 NAME

Krang::CGI::Schedule - web interface to manage scheduling for stories and media.

=head1 SYNOPSIS
                                                                                
  use Krang::CGI::History;
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
                            delete
                    )]);

    $self->tmpl_path('Schedule/');    
}
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
    my $object_type = $query->param('object_type');
    croak("Missing or invalid object type - must be 'story' or 'media'")
      if ( ($object_type ne 'story') and ($object_type ne 'media') );

    $template->param( is_story => 1 ) if ($object_type eq 'story');
    $template->param( is_media => 1 ) if ($object_type eq 'media');

    my $schedule_type = $query->param('advanced_schedule') ? 'advanced' : 'simple';
    ($schedule_type eq 'simple') ? $template->param( 'simple' => 1 ) : $template->param( 'advanced' => 1 );

    # Get media or story object from session -- or die() trying
    my $object = $self->get_object($object_type);
    my $object_id = ($object_type eq 'story') ? $object->story_id  :  $object->media_id;
    
    # populate read-only story/media metadata fields
    $template->param( 'id' => $object_id );
    $template->param( 'story_type' => $object->element->display_name ) if ($object_type eq 'story');
    $template->param( 'current_version' => $object->version );
    $template->param( 'published_version' => $object->published_version );
    $template->param( 'url' => $object->url );

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
        my %context = $schedule->context ? @{$schedule->context} : {};
        my $version = $context{'version'} ? $context{'version'} : '';
        push(@existing_schedule_loop, {
                                                'schedule_id' => $schedule->schedule_id,
                                                'time' => $schedule->next_run,
                                                'action' => $ACTION_LABELS{$schedule->action},
                                                'version' => $version
                                            });
    }

    return @existing_schedule_loop;
}

1;
