package Krang::CGI::Contrib;
use base qw(Krang::CGI);
use strict;
use warnings;


=head1 NAME

Krang::CGI::Contrib - web interface to manage Contributors


=head1 SYNOPSIS

  use Krang::CGI::Contrib;
  my $app = Krang::CGI::Contrib->new();
  $app->run();


=head1 DESCRIPTION

Krang::CGI::Contrib provides a web-based system
through which users can add, modify or delete
Contributors in a Krang instance.

This web application also provides facilities
through which Contributors may be associated
with Media and Story objects.


=head1 INTERFACE

Following are descriptions of all the run-modes
provided by Krang::CGI::Contrib.

The default run-mode (start_mode) for Krang::CGI::Contrib
is 'search'.

=head2 Run-Modes

=over 4

=cut


use Krang::Contrib;



##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
    my $self = shift;

    $self->start_mode('search');

    $self->run_modes([qw(
                         search
                         associate_story
                         associate_media
                         delete_selected
                         add
                         save_add
                         cancel_add
                         save_stay_add
                         edit
                         save_edit
                         cancel_edit
                         save_stay_edit
                         delete
                        )]);

    $self->tmpl_path('Contrib/');
}




##############################
#####  RUN-MODE METHODS  #####
##############################



=item search

Display a list of matching contributors, or all
contributors if no filter text is provided.

This run-mode expects two optional parameters:

  1. search_filter - Text string which is used to query contributors
  2. search_page   - Page number (0-based) of results to display.

=cut


sub search {
    my $self = shift;
    my %ui_messages = ( @_ );

    my $q = $self->query();
    my $t = $self->load_tmpl('list_view.tmpl', loop_context_vars=>1);

    $t->param(%ui_messages) if (%ui_messages);
#     $t->param(
#               message_contrib_added => 1,
#               message_add_cancelled => 1,
#               message_contrib_saved => 1,
#               message_save_cancelled => 1,
#               message_selected_deleted => 1,
#               message_contrib_deleted => 1,
#              );

    my @contributors = (
                        {
                         contrib_id => 1,
                         last => 'Erlbaum',
                         first => 'Jesse',
                         types => [{type_name=>'Writer'}]
                        },

                        {
                         contrib_id => 2,
                         last => 'Evil',
                         first => 'Dr.',
                         types => [{type_name=>'Mad Scientist'}]
                        },

                        {
                         contrib_id => 3,
                         last => 'Man',
                         first => 'Method',
                         types => [{type_name=>'Rhymer'}, {type_name=>'Writer'}]
                        },

                       );
    $t->param(contributors => \@contributors);

    return $t->output() . $self->dump_html();
}



=item associate_story

Invoked by direct link from Krang::CGI::Story, 
this run-mode provides an entry point through which
Contributors may be associated with Story objects.

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub associate_story {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}



=item associate_media

Invoked by direct link from Krang::CGI::Media, 
this run-mode provides an entry point through which
Contributors may be associated with Media objects.

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub associate_media {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}



=item delete_selected

Delete a set of contribuitors, specified by check-mark
on the "Contributor List" screen provided by the "search" 
run-mode.  Return to the "search" run-mode.

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub delete_selected {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}



=item add

Display an "Add Contributor" screen, through which
users may create a new Contributor object.

=cut


sub add {
    my $self = shift;

    my $q = $self->query();
    my $t = $self->load_tmpl("edit_view.tmpl");
    $t->param(add_mode => 1);

    return $t->output() . $self->dump_html();
}



=item save_add

Insert the Contributor object which was specified on the 
"Add Contributor" screen.  Return to the "search" run-mode.

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub save_add {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}



=item cancel_add

Cancel the addition of a Contributor object which was specified on the 
"Add Contributor" screen.  Return to the "search" run-mode.

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub cancel_add {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}



=item save_stay_add

Insert the Contributor object which was specified on the 
"Add Contributor" screen.  Go to the "Edit Contributor"
screen ("edit" run-mode), so that further edits may be made.

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub save_stay_add {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}



=item edit

Display an "Edit Contributor" screen, through which
users may edit an existing Contributor object.
Pre-populate form with properties of Contributor
selected on the "Contributor List" screen.

This run-mode expects to receive the required 
parameter "contrib_id".  It will croak() if this
parameter is missing or invalid.


=cut


sub edit {
    my $self = shift;

    my $q = $self->query();
    my $t = $self->load_tmpl("edit_view.tmpl");

    return $t->output() . $self->dump_html();
}



=item save_edit

Update the Contributor object as specified on the 
"Edit Contributor" screen.  Return to the "search" run-mode.

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub save_edit {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}



=item cancel_edit

Cancel the edit of the Contributor object currently on the 
"Edit Contributor" screen.  Return to the "search" run-mode.

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub cancel_edit {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}



=item save_stay_edit

Update the Contributor object as specified on the 
"Edit Contributor" screen.  Return to the "Edit Contributor"
screen ("edit" run-mode), so that further edits may be made.

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub save_stay_edit {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}



=item delete

Delete the Contributor object currently on the
"Edit Contributor" screen.  Return to the "search"
run-mode.

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub delete {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}




#############################
#####  PRIVATE METHODS  #####
#############################



1;


=back

=head1 AUTHOR

Jesse Erlbaum <jesse@erlbaum.net>


=head1 SEE ALSO

L<Krang::Contrib>, L<Krang::CGI>

=cut

