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

Krang::CGI::Contrib is expected to be invoked via a CGI
"instance script".  The requested run-mode is specified via 
the query parameter "rm".  For example, the following
request would invoke the "add" run-mode:

  http://server-name/contributor.pl?rm=add

Following are descriptions of all the run-modes provided 
by Krang::CGI::Contrib.  The default run-mode (start_mode) 
for Krang::CGI::Contrib is 'search'.


=head2 Run-Modes

=over 4

=cut


use Krang::Contrib;
use Krang::DB qw(dbh);


# Fields in a contrib
use constant CONTRIB_PROTOTYPE => {
                                contrib_id       => '',
                                bio              => '',
                                contrib_type_ids => [],
                                email            => '',
                                first            => '',
                                last             => '',
                                middle           => '',
                                phone            => '',
                                prefix           => '',
                                suffix           => '',
                                url              => '',
                               };



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

    # To be replaced with Krang::Contrib->simple_find( $q->param('search_filter') );
    my @contributors = Krang::Contrib->find();

    # To be replaced with paging
    my @contrib_tmpl_data = ( map { {
        contrib_id => $_->contrib_id(),
        last => $_->last(),
        first => $_->first(),
        types => [ map { { type_name => $_ } } ($_->contrib_type_names()) ]
    } } @contributors );

    $t->param(contributors => \@contrib_tmpl_data);

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
    my %ui_messages = ( @_ );

    my $q = $self->query();
    my $t = $self->load_tmpl("edit_view.tmpl");
    $t->param(add_mode => 1);
    $t->param(%ui_messages) if (%ui_messages);

    # Convert Krang::Contrib object to tmpl data
    my $contrib_tmpl = $self->get_contrib_tmpl();

    # Propagate to template
    $t->param($contrib_tmpl);

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

    return $self->add(
                      error_invalid_first => 1,
                      error_invalid_last => 1,
                      error_invalid_type => 1,
                     );
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
    my %ui_messages = ( @_ );

    my $q = $self->query();

    my $contrib_id = $q->param('contrib_id');
    my ( $c ) = Krang::Contrib->find( contrib_id=>$contrib_id);

    # Did we get our contributor?  Presumbably, users get here from a list.  IOW, there is 
    # no valid (non-fatal) case where a user would be here with an invalid contrib_id
    die ("No such contrib_id '$contrib_id'") unless (defined($c));

    my $t = $self->load_tmpl("edit_view.tmpl");
    $t->param(%ui_messages) if (%ui_messages);

    # Convert Krang::Contrib object to tmpl data
    my $contrib_tmpl = $self->get_contrib_tmpl($c);

    # Propagate to template
    $t->param($contrib_tmpl);

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

    return $self->edit(
                      error_invalid_first => 1,
                      error_invalid_last => 1,
                      error_invalid_type => 1,
                     );
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


# Return a hashref based on contributor properties, suitible 
# to be passed to an HTML::Template edit/add screen.
# If a $contributor object is supplied, use its properties 
# for default values.
sub get_contrib_tmpl {
    my $self = shift;
    my $c = shift || 0;

    my $q = $self->query();

    my %contrib_tmpl = ( %{&CONTRIB_PROTOTYPE} );

    # For each contrib prop, convert to HTML::Template compatible data
    foreach my $cf (keys(%contrib_tmpl)) {

        # Handle special case: contrib_type_ids multiple select
        if ($cf eq 'contrib_type_ids') {
            if (defined($q->param('first'))) {
                # If "first" was defined, assume that edit form has been submitted
                $contrib_tmpl{$cf} = [ $q->param('contrib_type_ids') ];
            } else {
                # No submission.  Load from database
                $contrib_tmpl{$cf} = [ $c->contrib_type_ids() ] if (ref($c));
            }
            next;
        }

        # Overlay query params
        my $query_val = $q->param($cf);
        if (defined($query_val)) {
            $contrib_tmpl{$cf} = $query_val;
        } else {
            # Handle simple (text) fields
            $contrib_tmpl{$cf} = $c->$cf if (ref($c));
        }
    }

    # Fix up contrib_type_ids to be tmpl-data
    my $all_contrib_types = $self->get_contrib_types();

    foreach my $ct (@$all_contrib_types) {
        my $contrib_type_id = $ct->{contrib_type_id};
        $ct->{selected} = 1 
          if ( grep { $_ eq $contrib_type_id } (@{$contrib_tmpl{contrib_type_ids}}) );
    }
    $contrib_tmpl{contrib_type_ids} = $all_contrib_types;

    # Return a reference to the tmpl-compat data
    return \%contrib_tmpl;
}


# Replace with Krang::Prefs(?)
sub get_contrib_types {
    my $self = shift;

    my $dbh = dbh();
    my $contrib_types = $dbh->selectall_arrayref("select contrib_type_id, type from contrib_type order by type");

    my @contrib_types_tmpl = ( map { {contrib_type_id=>$_->[0], type=>$_->[1]} } @$contrib_types );

    return \@contrib_types_tmpl;
}



1;


=back

=head1 AUTHOR

Jesse Erlbaum <jesse@erlbaum.net>


=head1 SEE ALSO

L<Krang::Contrib>, L<Krang::CGI>

=cut

