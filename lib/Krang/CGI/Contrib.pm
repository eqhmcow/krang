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
use Krang::Session qw(%session);


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

    return $t->output();
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

This mode expects the query param "contrib_delete_list"
to contain an array of contrib_id values which correspond
to contributor records to be deleted.

=cut


sub delete_selected {
    my $self = shift;

    my $q = $self->query();
    my @contrib_delete_list = ( $q->param('contrib_delete_list') );
    $q->delete('contrib_delete_list');

    # No selected contribs?  Just return to list view without any message
    return $self->search() unless (@contrib_delete_list);

    foreach my $cid (@contrib_delete_list) {
        Krang::Contrib->delete($cid);
    }

    return $self->search(message_selected_deleted=>1);
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

    # Make new Contrib, but don't save it
    my $c = Krang::Contrib->new();

    # Stash it in the session for later
    $session{EDIT_CONTRIB} = $c;

    # Convert Krang::Contrib object to tmpl data
    my $contrib_tmpl = $self->get_contrib_tmpl($c);

    # Propagate to template
    $t->param($contrib_tmpl);

    return $t->output();
}



=item save_add

Insert the Contributor object which was specified on the 
"Add Contributor" screen.  Return to the "search" run-mode.

This run-mode retrieves a temporary $contributor which was
created and stored in the %session by the "add" mode.  By 
working with a temporary contributor object we don't have
to worry about the user inadvertantly creating a deplicate
contributor if thay hit reload/refresh on their web browser.

This mode expects to receive parameters which match the name
of the contrib properties, excluding "contrib_id".

=cut


sub save_add {
    my $self = shift;

    my $q = $self->query();

    my %errors = ( $self->validate_contrib() );

    # Return to add screen if we have errors
    return $self->add( %errors ) if (%errors);

    # Retrieve new contrib object
    my $c = $session{EDIT_CONTRIB} || 0;
    die("Can't retrieve EDIT_CONTRIB from session") unless (ref($c));

    $self->do_update_contrib($c);

    return $self->search(message_contrib_added=>1);
}



=item cancel_add

Cancel the addition of a Contributor object which was specified on the 
"Add Contributor" screen.  Return to the "search" run-mode.

=cut


sub cancel_add {
    my $self = shift;

    my $q = $self->query();
    $q->delete( $q->param() );

    return $self->search(message_add_cancelled=>1);
}



=item save_stay_add

Insert the Contributor object which was specified on the 
"Add Contributor" screen.  Go to the "Edit Contributor"
screen ("edit" run-mode), so that further edits may be made.

This mode functions exactly the same as "save_add", with 
the exception that the user is returned to the "edit" mode
when they are done.

=cut


sub save_stay_add {
    my $self = shift;

    my $q = $self->query();

    my %errors = ( $self->validate_contrib() );

    # Return to add screen if we have errors
    return $self->add( %errors ) if (%errors);

    # Retrieve new contrib object
    my $c = $session{EDIT_CONTRIB} || 0;
    die("Can't retrieve EDIT_CONTRIB from session") unless (ref($c));

    $self->do_update_contrib($c);

    # Set up for edit mode
    my $contrib_id = $c->contrib_id();
    $q->delete( $q->param() );
    $q->param(contrib_id => $contrib_id);
    $q->param(rm => 'edit');

    return $self->edit(message_contrib_added=>1);
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

    # Stash it in the session for later
    $session{EDIT_CONTRIB} = $c;

    my $t = $self->load_tmpl("edit_view.tmpl");
    $t->param(%ui_messages) if (%ui_messages);

    # Convert Krang::Contrib object to tmpl data
    my $contrib_tmpl = $self->get_contrib_tmpl($c);

    # Propagate to template
    $t->param($contrib_tmpl);

    return $t->output();
}



=item save_edit

Update the Contributor object as specified on the 
"Edit Contributor" screen.  Return to the "search" run-mode.

This run-mode retrieves the $contributor which was
created and stored in the %session by the "edit" mode.

This mode expects to receive parameters which match the name
of the contrib properties.  This parameters will override 
the properties of the contributor which are in the database,
except for "contrib_id" which cannot be changed.

=cut


sub save_edit {
    my $self = shift;

    my $q = $self->query();

    my %errors = ( $self->validate_contrib() );

    # Return to edit screen if we have errors
    return $self->edit( %errors ) if (%errors);

    # Retrieve new contrib object
    my $c = $session{EDIT_CONTRIB} || 0;
    die("Can't retrieve EDIT_CONTRIB from session") unless (ref($c));

    $self->do_update_contrib($c);

    return $self->search(message_contrib_saved=>1);
}



=item cancel_edit

Cancel the edit of the Contributor object currently on the 
"Edit Contributor" screen.  Return to the "search" run-mode.

=cut


sub cancel_edit {
    my $self = shift;

    my $q = $self->query();
    $q->delete( $q->param() );

    return $self->search(message_save_cancelled=>1);
}



=item save_stay_edit

Update the Contributor object as specified on the 
"Edit Contributor" screen.  Return to the "Edit Contributor"
screen ("edit" run-mode), so that further edits may be made.

This mode functions exactly the same as "save_edit", with 
the exception that the user is returned to the "edit" mode
when they are done.

=cut


sub save_stay_edit {
    my $self = shift;

    my $q = $self->query();

    my %errors = ( $self->validate_contrib() );

    # Return to edit screen if we have errors
    return $self->edit( %errors ) if (%errors);

    # Retrieve new contrib object
    my $c = $session{EDIT_CONTRIB} || 0;
    die("Can't retrieve EDIT_CONTRIB from session") unless (ref($c));

    $self->do_update_contrib($c);

    # Set up for edit mode
    my $contrib_id = $c->contrib_id();
    $q->delete( $q->param() );
    $q->param(contrib_id => $contrib_id);
    $q->param(rm => 'edit');

    return $self->edit(message_contrib_saved=>1);
}



=item delete

Delete the Contributor object currently on the
"Edit Contributor" screen.  Return to the "search"
run-mode.

This mode expects to receive a query parameter
"contrib_id" which contains the contributor to
be deleted.

=cut


sub delete {
    my $self = shift;

    my $q = $self->query();
    my $contrib_id = $q->param('contrib_id');

    # Check the session.  Is this contrib stashed there?  (Clean, if so.)
    my $c = $session{EDIT_CONTRIB} || 0;
    if (ref($c) && (($c->contrib_id() || '') eq $contrib_id)) {
        # Delete contrib and clear from session
        $c->delete();
        delete($session{EDIT_CONTRIB});
    } else {
        # Delete this contrib by contrib_id
        Krang::Contrib->delete($contrib_id);
    }

    return $self->search(message_contrib_deleted=>1);
}




#############################
#####  PRIVATE METHODS  #####
#############################


# Updated the provided Contrib object with data
# from the CGI query
sub do_update_contrib {
    my $self = shift;
    my $contrib = shift;

    my $q = $self->query();

    # Get prototype for the purpose of update
    my %contrib_prototype = ( %{&CONTRIB_PROTOTYPE} );

    # We can't update contrib_id
    delete($contrib_prototype{contrib_id});

    # contrib_type_ids is a special case
    # delete($contrib_prototype{contrib_type_ids});

    # Grab each CGI query param and set the corresponding Krang::Contrib property
    foreach my $ck (keys(%contrib_prototype)) {
        # Presumably, query data is already validated and un-tainted
        $contrib->$ck($q->param($ck));
    }

    # Write back to database
    $contrib->save();
}


# Examine the query data to validate that the submitted
# contributor is valid.  Return hash-errors, if any.
sub validate_contrib {
    my $self = shift;

    my $q = $self->query();

    my %errors = ();

    # Validate first name
    my $first = $q->param('first');
    $errors{error_invalid_first} = 1
      unless (defined($first) && ($first =~ /\S+/));

    # Validate last name
    my $last = $q->param('last');
    $errors{error_invalid_last} = 1
      unless (defined($last) && ($last =~ /\S+/));

    # Validate contrib types
    # contrib_type_ids
    my @contrib_type_ids = ( $q->param('contrib_type_ids') );
    my $all_contrib_types = $self->get_contrib_types();
    my @valid_contrib_type_ids = ();
    foreach my $ctype (@contrib_type_ids) {
        my $is_valid = grep { $_->[0] eq $ctype } @$all_contrib_types;
        push (@valid_contrib_type_ids, $ctype) if ($is_valid);
    }
    $q->delete('contrib_type_ids');
    $q->param('contrib_type_ids', @valid_contrib_type_ids );
    $errors{error_invalid_type} = 1 unless (scalar(@valid_contrib_type_ids));

    return %errors;
}


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

    my @contrib_types_tmpl = ();
    foreach my $ct (@$all_contrib_types) {
        my $contrib_type_id = $ct->[0];
        my $type = $ct->[1];
        my $selected = ( grep { $_ eq $contrib_type_id } (@{$contrib_tmpl{contrib_type_ids}}) );

        push(@contrib_types_tmpl, {
                                   contrib_type_id => $contrib_type_id,
                                   type => $type,
                                   selected => $selected,
                                  });
    }
    $contrib_tmpl{contrib_type_ids} = \@contrib_types_tmpl;

    # Return a reference to the tmpl-compat data
    return \%contrib_tmpl;
}


# Replace with Krang::Prefs(?)
sub get_contrib_types {
    my $self = shift;

    my $dbh = dbh();
    my $contrib_types = $dbh->selectall_arrayref("select contrib_type_id, type from contrib_type order by type");

    return $contrib_types;
}


1;


=back

=head1 AUTHOR

Jesse Erlbaum <jesse@erlbaum.net>


=head1 SEE ALSO

L<Krang::Contrib>, L<Krang::CGI>

=cut

