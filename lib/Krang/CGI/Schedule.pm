package Krang::CGI::Schedule;
use base qw(Krang::CGI);
use strict;
use warnings;

use Carp qw(croak);
use Krang::Schedule;
use Krang::Message qw(add_message);

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

    $self->start_mode('show');
    
    $self->run_modes([qw(
                            show
                            add
                            delete
                    )]);

    $self->tmpl_path('Schedule/');    
}
=item show
                                                                                
Display the current schedule associated with the story/media object and
allow deletions and additions to the schedule. The following parameters 
are used with this runmode:

=over 4
                                                                                
=item story_id

=item media_id

One of these (and only one) must be set to the ID of the object in
question.

=item return_script
                                                                                
This must name the script to return to when the user clicks the return
button.  For example, when calling schedule.pl from story.pl I would
include:
                                                                                
  <input name=return_script value=story.pl type=hidden>

=item return_params
                                                                                
This must be set to a list of key-value pairs which will be submitted
back to the script specified by return_script.  For example,
to return to story edit mode after viewing the log these parameters
might be used:
                                                                                
  <input name=return_params value=rm   type=hidden>
  <input name=return_params value=edit type=hidden>
                                                                                
=back
                                                                                
=cut

sub show {

}

1;
