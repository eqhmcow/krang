package Krang::CGI::Media;
use base qw(Krang::CGI);
use strict;
use warnings;




=head1 NAME

Krang::CGI::Media - web interface to manage media


=head1 SYNOPSIS

  use Krang::CGI::Media;
  my $app = Krang::CGI::Media->new();
  $app->run();


=head1 DESCRIPTION

Krang::CGI::Media provides a web-based system
through which users can add, modify, delete, 
check out, or publish media.


=head1 INTERFACE

Following are descriptions of all the run-modes
provided by Krang::CGI::Media.

The default run-mode (start_mode) for Krang::CGI::Media
is 'add'.

=head2 Run-Modes

=over 4

=cut

use Krang::Category;
use Krang::Media;
use Krang::Widget qw(category_chooser datetime_chooser decode_datetime format_url);
use Krang::Message qw(add_message);
use Krang::HTMLPager;
use Krang::Pref;
use Krang::Session qw(%session);
use Carp qw(croak);


use constant WORKSPACE_URI => 'workspace.pl';


##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
    my $self = shift;

    $self->start_mode('add');

    $self->run_modes([qw(
                         find
                         advanced_find
                         add
                         save_add
                         cancel_add
                         checkin_add
                         checkin_edit
                         save_stay_add
                         checkout_and_edit
                         edit
                         save_edit
                         save_stay_edit
                         delete
                         delete_selected
                         save_and_associate_media
                         save_and_view_log
                         view
                         view_version
                         revert_version
                         save_and_edit_schedule
                        )]);

    $self->tmpl_path('Media/');
}




##############################
#####  RUN-MODE METHODS  #####
##############################




=item find

The find mode allows the user to run a "simple search" on 
media objects, which will be listed on a paging view.

From this paging view the user may choose to edit or view
an object, or select a set of objects to be deleted.

=cut


sub find {
    my $self = shift;

    my $q = $self->query();
    my $t = $self->load_tmpl('list_view.tmpl', associate=>$q);

    # Persist data for return from view in "return_params"
    my @return_param_list = qw(
                                       rm
                                       krang_pager_curr_page_num 
                                       krang_pager_show_big_view 
                                       krang_pager_sort_field 
                                       krang_pager_sort_order_desc 
                                       search_filter 
                                       show_thumbnails 
                                      );
    $t->param(return_params => $self->make_return_params(@return_param_list));

    my $search_filter = $q->param('search_filter');
    my $show_thumbnails = $q->param('show_thumbnails');
    unless (defined($search_filter)) {
        # Define search_filter
        $search_filter = '';

        # Undefined search_filter probably means it's the first time we're here.
        # Set show_thumbnails to '1' by default
        $show_thumbnails = 1;
    } else {
        # If search_filter is defined, but not show_thumbnails, assume show_thumbnails is false
        $show_thumbnails = 0 unless (defined($show_thumbnails));
    }

    my $persist_vars = {
                        rm => 'find',
                        search_filter => $search_filter,
                        show_thumbnails => $show_thumbnails,
                       };

    my $find_params = { simple_search => $search_filter };

    my $pager = $self->make_pager($persist_vars, $find_params, $show_thumbnails);

    # Run pager
    $t->param(pager_html => $pager->output());
    $t->param(row_count => $pager->row_count());
    $t->param(show_thumbnails => $show_thumbnails);

    return $t->output();
}





=item advanced_find

The find mode allows the user to run an "advanced search" on 
media objects, which will be listed on a paging view.

From this paging view the user may choose to edit or view
an object, or select a set of objects to be deleted.

=cut


sub advanced_find {
    my $self = shift;

    my $q = $self->query();
    my $t = $self->load_tmpl('list_view.tmpl', associate=>$q);
    $t->param(do_advanced_search=>1);

    # Persist data for return from view in "return_params"
    my @return_param_list = qw(
                                       rm
                                       krang_pager_curr_page_num 
                                       krang_pager_show_big_view 
                                       krang_pager_sort_field 
                                       krang_pager_sort_order_desc 
                                       show_thumbnails 
                                       search_below_category_id 
                                       search_filename 
                                       search_filter 
                                       search_media_id 
                                       search_title 
                                       search_creation_date_day 
                                       search_creation_date_month 
                                       search_creation_date_year
                                       search_creation_date_hour
                                       search_creation_date_minute
                                       search_creation_date_ampm 
                                      );
    $t->param(return_params => $self->make_return_params(@return_param_list));

    my $persist_vars = { rm => 'advanced_find' };
    my $find_params = {};

    my $show_thumbnails = $q->param('show_thumbnails');
    $show_thumbnails = 0 unless (defined($show_thumbnails));
    $persist_vars->{show_thumbnails} = $show_thumbnails;

    # Build find params
    my $search_below_category_id = $q->param('search_below_category_id');
    if ($search_below_category_id) {
        $persist_vars->{search_below_category_id} = $search_below_category_id;
        $find_params->{below_category_id} = $search_below_category_id;
    }

    my $search_creation_date = decode_datetime(
                                           query => $q,
                                           name => 'search_creation_date',
                                          );
    if ($search_creation_date) {
        # If date is valid send it to search and persist it.
        $find_params->{creation_date} = $search_creation_date;
        for (qw/day month year hour minute ampm/) {
            my $varname = "search_creation_date_$_";
            $persist_vars->{$varname} = $q->param($varname);
        }
    } else {
        # Delete date chooser if date is incomplete
        for (qw/day month year hour minute ampm/) {
            my $varname = "search_creation_date_$_";
            $q->delete($varname);
        }
    }

    # search_filename
    my $search_filename = $q->param('search_filename');
    if ($search_filename) {
        $search_filename =~ s/\W+/\%/g;
        $find_params->{filename_like} = "\%$search_filename\%";
        $persist_vars->{search_filename} = $search_filename;
    }

    # search_title
    my $search_title = $q->param('search_title');
    if ($search_title) {
        $search_title =~ s/\W+/\%/g;
        $find_params->{title_like} = "\%$search_title\%";
        $persist_vars->{search_title} = $search_title;
    }

    # search_media_id
    my $search_media_id = $q->param('search_media_id');
    if ($search_media_id) {
        $find_params->{media_id} = $search_media_id;
        $persist_vars->{search_media_id} = $search_media_id;
    }

    # search_no_attributes
    my $search_no_attributes = $q->param('search_no_attributes');
    if ($search_no_attributes) {
        $find_params->{no_attributes} = $search_no_attributes;
        $persist_vars->{search_no_attributes} = $search_no_attributes;
    }

    # Run pager
    my $pager = $self->make_pager($persist_vars, $find_params, $show_thumbnails);
    $t->param(pager_html => $pager->output());
    $t->param(row_count => $pager->row_count());

    # Set up advanced search form
    $t->param(category_chooser => category_chooser(
                                                 query => $q,
                                                 name => 'search_below_category_id',
                                                 formname => 'search_form',
                                                ));
    $t->param(date_chooser => datetime_chooser(
                                           query => $q,
                                           name => 'search_creation_date',
                                           nochoice =>1,
                                          ));

    return $t->output();
}





=item add

The "add" run-mode displays the form through which
new Media objects may be added to Krang.

=cut


sub add {
    my $self = shift;
    my %args = ( @_ );

    # Create new temporary Media object to work on
    my $m = Krang::Media->new();
    $session{media} = $m;

    # Call and return the real add function
    return $self->_add(%args);
}





=item save_add

Save the new media object, check it out, and redirect to Workspace.

This run-mode expects to find media object in session.

=cut


sub save_add {
    my $self = shift;

    my $q = $self->query();

    my $m = $session{media};
    die ("No media object in session") unless (ref($m));

    # Update object in session
    $self->update_media($m);

    # Validate input.  Return errors, if any.
    my %errors = $self->validate_media($m);
    return $self->_add(%errors) if (%errors);

    # Save object to database
    my %save_errors = ( $self->do_save_media($m) );
    return $self->_add(%save_errors) if (%save_errors);

    # Checkout to Workspace
    $m->checkout();

    # Notify user
    add_message("new_media_saved");

    # Redirect to workspace.pl
    my $uri = WORKSPACE_URI;
    $self->header_props(-uri => $uri);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$uri\">$uri</a>";
}

=item checkin_add 

Save the new media object, then check it in. Redirect to 
My Workspace afterwards, even tho the media object will not be there.

=cut

sub checkin_add {
    my $self = shift;
                                                                             
    my $q = $self->query();
                                                                             
    my $m = $session{media};
    die ("No media object in session") unless (ref($m));
                                                                             
    # Update object in session
    $self->update_media($m);
                                                                             
    # Validate input.  Return errors, if any.
    my %errors = $self->validate_media($m);
    return $self->_add(%errors) if (%errors);
                                                                             
    # Save object to database
    my %save_errors = ( $self->do_save_media($m) );
    return $self->_add(%save_errors) if (%save_errors);
    
    # check in
    $m->checkin();

    # Notify user
    add_message("new_media_saved");

    # Redirect to workspace.pl
    my $uri = WORKSPACE_URI;
    $self->header_props(-uri => $uri);
    $self->header_type('redirect');
                                                                             
    return "Redirect: <a href=\"$uri\">$uri</a>";

}


=item cancel_add

Called when user clicks "delete" from an add new media screen.
This mode removes the currewnt media object from the session
and redirects the user to the Workspace.


=cut


sub cancel_add {
    my $self = shift;

    my $q = $self->query();

    # Remove media from session
    delete($session{media});

    add_message('message_media_deleted');

    # Redirect to workspace
    my $workspace_uri = WORKSPACE_URI;
    $self->header_props(-uri=>$workspace_uri);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$workspace_uri\">$workspace_uri</a>";
}





=item save_stay_add

Functions the same as save_add, except user is
redirected to edit screen with same object.

=cut


sub save_stay_add {
    my $self = shift;

    my $q = $self->query();

    my $m = $session{media};
    die ("No media object in session") unless (ref($m));

    # Update object in session
    $self->update_media($m);

    # Validate input.  Return errors, if any.
    my %errors = $self->validate_media($m);
    return $self->_add(%errors) if (%errors);

    # Save object to database
    my %save_errors = ( $self->do_save_media($m) );
    return $self->_add(%save_errors) if (%save_errors);

    # Checkout to Workspace
    $m->checkout();

    # Notify user
    add_message("new_media_saved");

    # Redirect to edit mode
    my $url = $q->url(-relative=>1);
    $url .= "?rm=edit&media_id=". $m->media_id();
    $self->header_props(-url=>$url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}


=item checkout_and_edit

Checks out the media object identified by media_id and sends the user
to edit.

=cut

sub checkout_and_edit {
    my $self = shift;
    my $q = $self->query();

    my $media_id = $q->param('media_id');
    croak("Missing required media_id parameter.") unless $media_id;

    my ($m) = Krang::Media->find(media_id=>$media_id);
    croak("Unable to load media_id '$media_id'") unless $m;

    $m->checkout;
    return $self->edit;
}


=item edit

The "edit" mode displays the form through which
users may edit existing Media objects.

=cut


sub edit {
    my $self = shift;
    my %args = ( @_ );

    my $q = $self->query();

    # Retrieve object from session or create it if it doesn't exist
    my $media_id = $q->param('media_id');
    $media_id = '' unless (defined($media_id));

    # Case 1:  We've been directed here via associate-return, with a new Media object
    #           - Have object in session.
    #           - No media_id in CGI form data.  No ID in object either.
    # Case 2:  We've been directed here via associate-return, with an existing Media object
    #           - Have object in session.
    #           - No media_id in CGI form data.  We have ID in object.
    # Case 3:  User hit back and went to edit a different object.
    #           - Have media_id in CGI form data.
    # Case 4:  User returned to edit because of form error
    #           - Have media_id in CGI form data.
    #
    unless ($media_id || (ref($session{media}) && ($session{media}->media_id))) {
        # In this case, we expect a Media object in the session
        # which lacks an ID
        my $m = $session{media};
        die ("Missing media_id, but not in add mode") unless (ref($m) && not($m->media_id));

        # Redirect to add mode
        return $self->_add(%args);
    }

    # Load media object into session, or die trying
    my $m = $session{media};
    my $force_reload = $q->param('force_reload');
    if ( ($force_reload) or ( $media_id  &&  not(ref($m) && defined($media_id) && ($media_id eq $m->media_id))) ) {
        # If we have a media_id, force load using it.
        ($m) = Krang::Media->find(media_id=>$media_id);
        $session{media} = $m;
    }

    die ("Can't find media object with media_id '$media_id'") unless (ref($m));

    my $t = $self->load_tmpl('edit_media.tmpl', associate=>$q, loop_context_vars=>1);

    my $media_tmpl_data = $self->make_media_tmpl_data($m);
    $t->param($media_tmpl_data);

    # Propagate messages, if we have any
    $t->param(%args) if (%args);

    return $t->output();
}





=item save_edit

Validate and save the form content to the media object.
Redirect the user to their Workspace.

=cut


sub save_edit {
    my $self = shift;

    my $q = $self->query();

    my $m = $session{media};
    die ("No media object in session") unless (ref($m));

    # Update object in session
    $self->update_media($m);

    # Validate input.  Return errors, if any.
    my %errors = $self->validate_media($m);
    return $self->edit(%errors) if (%errors);

    # Save object to database
    my %save_errors = ( $self->do_save_media($m) );
    return $self->edit(%save_errors) if (%save_errors);

    # Checkout to Workspace
    $m->checkout();

    # Notify user
    add_message("media_saved");

    # Redirect to workspace.pl
    my $uri = WORKSPACE_URI;
    $self->header_props(-uri=>$uri);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$uri\">$uri</a>";
}

=item checkin_edit

Validate and save the form content to the media object.
Checkin media object.
Redirect the user to their Workspace.

=cut

sub checkin_edit {
    my $self = shift;
                                                                             
    my $q = $self->query();
                                                                             
    my $m = $session{media};
    die ("No media object in session") unless (ref($m));
                                                                             
    # Update object in session
    $self->update_media($m);
                                                                             
    # Validate input.  Return errors, if any.
    my %errors = $self->validate_media($m);
    return $self->edit(%errors) if (%errors);
                                                                             
    # Save object to database
    my %save_errors = ( $self->do_save_media($m) );
    return $self->edit(%save_errors) if (%save_errors);
                                                                             
    # Checkin
    $m->checkin();
                                                                             
    # Notify user
    add_message("media_saved");
                                                                             
    # Redirect to workspace.pl
    my $uri = WORKSPACE_URI;
    $self->header_props(-uri=>$uri);
    $self->header_type('redirect');
                                                                             
    return "Redirect: <a href=\"$uri\">$uri</a>";
}



=item save_stay_edit

Validate and save the form content to the media object.
Return the user to the edit screen.


=cut


sub save_stay_edit {
    my $self = shift;

    my $q = $self->query();

    my $m = $session{media};
    die ("No media object in session") unless (ref($m));

    # Update object in session
    $self->update_media($m);

    # Validate input.  Return errors, if any.
    my %errors = $self->validate_media($m);
    return $self->edit(%errors) if (%errors);

    # Save object to database
    my %save_errors = ( $self->do_save_media($m) );
    return $self->edit(%save_errors) if (%save_errors);

    # Checkout to Workspace
    $m->checkout();

    # Notify user
    add_message("media_saved");

    # Redirect to edit mode
    my $url = $q->url(-relative=>1);
    $url .= "?rm=edit&media_id=". $m->media_id();
    $self->header_props(-url=>$url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}





=item delete

Delete the media object specified by CGI form 
parameter 'media_id'.  Redirect user to Workspace.

=cut


sub delete {
    my $self = shift;

    my $q = $self->query();
    my $media_id = $q->param('media_id');

    # Check the session.  Is this media stashed there?  (Clean, if so.)
    my $m = $session{media} || 0;
    if (ref($m) && (($m->media_id() || '') eq $media_id)) {
        # Delete media and clear from session
        $m->delete();
        delete($session{media});
    } else {
        # Delete this media by media_id
        my $m = Krang::Media->find(media_id=>$media_id);
        $m->delete();
    }

    add_message('message_media_deleted');

    # Redirect to workspace
    my $workspace_uri = WORKSPACE_URI;
    $self->header_props(-uri => $workspace_uri);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$workspace_uri\">$workspace_uri</a>";
}





=item delete_selected

Delete the media objects which have been selected (checked)
from the find mode list view.  This mode expects selected 
media objects to be specified in the CGI param 
'krang_pager_rows_checked'.


=cut


sub delete_selected {
    my $self = shift;

    my $q = $self->query();
    my @media_delete_list = ( $q->param('krang_pager_rows_checked') );
    $q->delete('krang_pager_rows_checked');

    # No selected contribs?  Just return to list view without any message
    return $self->find() unless (@media_delete_list);

    foreach my $mid (@media_delete_list) {
        my ($m) = Krang::Media->find( media_id => $mid);
        $m->delete();
    }

    add_message('message_selected_deleted');
    return $self->find();
}

=item save_and_edit_schedule
                                                                                
This mode saves the current data to the session and passes control to
edit schedule for story.
                                                                                
=cut
                                                                                
sub save_and_edit_schedule {
    my $self = shift;
                                                                                
    # Update media object
    my $m = $session{media};
    $self->update_media($m);
                                                                            
    $self->header_props(-uri => 'schedule.pl?rm=edit&object_type=media');
    $self->header_type('redirect');
    return;
}

=item save_and_associate_media

The purpose of this mode is to hand the user off to the
associate contribs screen.  This mode writes changes back 
to the media object without calling save().  When done,
it performs an HTTP redirect to:

  contributor.pl?rm=associate_media

=cut


sub save_and_associate_media {
    my $self = shift;

    my $q = $self->query();

    # Update media object
    my $m = $session{media};
    $self->update_media($m);

    # Redirect to associate screen
    my $url = 'contributor.pl?rm=associate_media';
    $self->header_props(-uri=>$url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}


=item save_and_view_log

The purpose of this mode is to hand the user off to the log viewng
screen.  This mode writes changes back to the media object without
calling save().  When done, it performs an HTTP redirect to
history.pl.

=cut


sub save_and_view_log {
    my $self = shift;

    my $q = $self->query();

    # Update media object
    my $m = $session{media};
    $self->update_media($m);

    # Redirect to associate screen
    my $url = 'history.pl?history_return_script=media.pl&return_params=rm&return_params=edit&media_id=' . $m->media_id;
    $self->header_props(-uri=>$url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}


=item view

Display the specified media object in a view form.


=cut


sub view {
    my $self = shift;
    my $version = shift;

    my $q = $self->query();
    my $t = $self->load_tmpl('view_media.tmpl');

    # Retrieve object from session or create it if it doesn't exist
    my $media_id = $q->param('media_id');
    die ("No media_id specified") unless ($media_id);

    # Load media object into session, or die trying
    my %find_params = ();
    $find_params{media_id} = $media_id;

    # Handle viewing old version
    if ($version) {
        $find_params{version} = $version;
        $t->param(is_old_version => 1);
    }

    my ($m) = Krang::Media->find(%find_params);
    die ("Can't find media object with media_id '$media_id'") unless (ref($m));

    my $media_view_tmpl_data = $self->make_media_view_tmpl_data($m);
    $t->param($media_view_tmpl_data);

    return $t->output();
}





=item view_version

Display the specified version of the media object in a view form.

=cut


sub view_version {
    my $self = shift;

    my $q = $self->query();
    my $selected_version = $q->param('selected_version');

    die ("Invalid selected version '$selected_version'") 
      unless ($selected_version and $selected_version =~ /^\d+$/);

    # Update media object
    my $m = $session{media};
    $self->update_media($m);

    # Return view mode with version
    return $self->view($selected_version);
}





=item revert_version

Send the user to an edit screen, replacing the object with the 
specified version of itself.

=cut


sub revert_version {
    my $self = shift;

    my $q = $self->query();
    my $selected_version = $q->param('selected_version');

    die ("Invalid selected version '$selected_version'") 
      unless ($selected_version and $selected_version =~ /^\d+$/);

    # Perform revert
    my $m = $session{media};
    $m->revert($selected_version);

    # Inform user
    add_message("message_revert_version", version => $selected_version);

    # Redirect to edit mode
    my $url = $q->url(-relative=>1);
    $url .= "?rm=edit";
    $self->header_props(-url=>$url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}







#############################
#####  PRIVATE METHODS  #####
#############################

# Validate media object to check validity.  Return errors as hash and add_message()s.
# Must pass in $media object
sub validate_media {
    my $self = shift;
    my $media = shift;

    # Errors array
    my @errors = ();

    # Validate: title
    my $title = $media->title();
    push(@errors, 'error_invalid_title') unless ($title && ($title =~ /\S+/));

    # Validate: media_type_id
    my $media_type_id = $media->media_type_id();
    push(@errors, 'error_media_type_id') unless ($media_type_id);

    # Validate: category_id
    my $category_id = $media->category_id();
    push(@errors, 'error_category_id') unless ($category_id);

    # Validate: media_file
    my $media_file = $media->filename();
    push(@errors, 'error_media_file') unless ($media_file);

    # Add messages, return hash for errors
    my %hash_errors = ();
    foreach my $error (@errors) {
        add_message($error);
        $hash_errors{$error} = 1;
    }

    return %hash_errors;
}


# Return an add form.  This method expects a media object in the session.
sub _add {
    my $self = shift;
    my %args = ( @_ );

    my $q = $self->query();
    my $t = $self->load_tmpl('edit_media.tmpl', associate=>$q, loop_context_vars=>1);
    $t->param(add_mode => 1);

    # Retrieve object from session or create it if it doesn't exist
    # or if we've got a non-new object. (Case:  Abandoned edit object.)
    my $m = $session{media};
    die ("No media object in session") unless (ref($m));

    my $media_tmpl_data = $self->make_media_tmpl_data($m);
    $t->param($media_tmpl_data);

    # Propagate messages, if we have any
    $t->param(%args) if (%args);

    return $t->output();
}


# Update the provided Media object with data from the CGI form.
# Does NOT call save
sub update_media {
    my $self = shift;
    my $m = shift;

    my $q = $self->query();

    my @m_fields = qw(
                      title
                      media_type_id 
                      category_id 
                      media_file 
                      caption 
                      copyright 
                      alt_tag 
                      notes 
                     );
    foreach my $mf (@m_fields) {
        # Handle file upload
        if ($mf eq 'media_file') {
            my $filehandle = $q->upload('media_file');
            next unless ($filehandle);

            my $media_file = $q->param('media_file');

            # Coerce a reasonable name from what we get
            my @filename_parts = split(/[\/\\\:]/, $media_file);
            my $filename = $filename_parts[-1];

            # Put the file in the Media object
            $m->upload_file(filehandle => $filehandle,
                            filename => $filename);

            # Clear param and continue
            $q->delete($mf);
            next;
        }

        # Default: Grab scalar value from CGI form
        my $val = $q->param($mf);
        $m->$mf( $val );

        # Clear param and continue
        $q->delete($mf);
    }

    # Done!
}


# Given a media object, $m, return a hashref with all the data needed
# for the edit template.
sub make_media_tmpl_data {
    my $self = shift;
    my $m = shift;

    my $q = $self->query();
    my %tmpl_data = ();

    # Set up details only found on edit (not add) view
    if ($tmpl_data{media_id} = $m->media_id()) {
        my $thumbnail_path = $m->thumbnail_path(relative => 1) || '';
        $tmpl_data{thumbnail_path} = $thumbnail_path;
        $tmpl_data{url} = format_url( url => $m->url(),
                                      linkto => "javascript:preview_media_session()",
                                      length => 50 );
        $tmpl_data{published_version} = $m->published_version();
        $tmpl_data{version} = $m->version();

        # Display creation_date
        my $creation_date = $m->creation_date();
        $tmpl_data{creation_date} = $creation_date->strftime('%b %e, %Y %l:%M %p');

        # Set up versions drop-down
        my $curr_version = $tmpl_data{version};
        my $media_version_chooser = $q->popup_menu(
                                                   -name => 'selected_version',
                                                   -values => [1..$curr_version],
                                                   -default => $curr_version,
                                                   -override => 1,
                                                  );
        $tmpl_data{media_version_chooser} = $media_version_chooser;
    }

    # Build type drop-down
    my %media_types = Krang::Pref->get('media_type');
    my @media_type_ids = ( "", keys(%media_types) );
    my $media_types_popup_menu = $q->popup_menu(
                                                -name => 'media_type_id',
                                                -values => \@media_type_ids,
                                                -labels => \%media_types,
                                                -default => $m->media_type_id(),
                                               );
    $tmpl_data{type_chooser} = $media_types_popup_menu;

    # Build category chooser
    my $category_id = $q->param('category_id');
    $q->param('category_id', $m->category_id) unless ($category_id);
    my $category_chooser = category_chooser(
                                            query => $q,
                                            name => 'category_id',
                                            formname => 'edit_media_form',
                                           );
    $tmpl_data{category_chooser} = $category_chooser;

    # If we have a filename, show it.
    $tmpl_data{file_size} = sprintf("%.1fk", ($m->file_size() / 1024))
      if ($tmpl_data{filename}  = $m->filename());

    # Set up Contributors
    my @contribs = ();
    my %contrib_types = Krang::Pref->get('contrib_type');
    foreach my $c ($m->contribs()) {
        my %contrib_row = (
                           first => $c->first(),
                           last => $c->last(),
                           type => $contrib_types{ $c->selected_contrib_type() },
                          );
        push(@contribs, \%contrib_row);
    }
    $tmpl_data{contribs} = \@contribs;

    # Handle simple scalar fields
    my @m_fields = qw(
                      title
                      caption 
                      copyright 
                      alt_tag 
                      notes 
                     );
    foreach my $mf (@m_fields) {
        # Copy data from object into %tmpl_data
        # unless key exists in CGI data already
        unless (defined($q->param($mf))) {
            $tmpl_data{$mf} = $m->$mf();
        }
    }

    # Persist data for return from view in "return_params"
    $tmpl_data{return_params} = $self->make_return_params('rm');

    # Send data back to caller for inclusion in template
    return \%tmpl_data;
}


# Given a media object, $m, return a hashref with all the data needed
# for the view template
sub make_media_view_tmpl_data {
    my $self = shift;
    my $m = shift;

    my $q = $self->query();
    my %tmpl_data = ();

    $tmpl_data{media_id} = $m->media_id();

    my $thumbnail_path = $m->thumbnail_path(relative => 1) || '';
    $tmpl_data{thumbnail_path} = $thumbnail_path;

    $tmpl_data{url} = format_url( url => $m->url(),
                                  linkto => "javascript:preview_media('". $tmpl_data{media_id} ."')",
                                  length => 50 );

    $tmpl_data{published_version} = $m->published_version();

    $tmpl_data{version} = $m->version();

    # Display media type name
    my %media_types = Krang::Pref->get('media_type');
    my $media_type_id = $m->media_type_id();
    $tmpl_data{type} = $media_types{$media_type_id} if ($media_type_id);

    # Display category
    my $category_id = $m->category_id();
    my ($category) = Krang::Category->find(category_id => $category_id);
    $tmpl_data{category} = format_url( url => $category->url(),
                                       length => 50 );

    # If we have a filename, show it.
    $tmpl_data{file_size} = sprintf("%.1fk", ($m->file_size() / 1024))
      if ($tmpl_data{filename}  = $m->filename());

    # Set up Contributors
    my @contribs = ();
    my %contrib_types = Krang::Pref->get('contrib_type');
    foreach my $c ($m->contribs()) {
        my %contrib_row = (
                           first => $c->first(),
                           last => $c->last(),
                           type => $contrib_types{ $c->selected_contrib_type() },
                          );
        push(@contribs, \%contrib_row);
    }
    $tmpl_data{contribs} = \@contribs;
    $tmpl_data{return_script} = $q->param('return_script');

    # Display creation_date
    my $creation_date = $m->creation_date();
    $tmpl_data{creation_date} = $creation_date->strftime('%b %e, %Y %l:%M %p');
 
    # Handle simple scalar fields
    my @m_fields = qw(
                      title
                      caption 
                      copyright 
                      alt_tag 
                      notes 
                     );
    foreach my $mf (@m_fields) {
        # Copy data from object into %tmpl_data
        # unless key exists in CGI data already
        unless (defined($q->param($mf))) {
            $tmpl_data{$mf} = $m->$mf();
        }
    }

    # Set up return state
    my %return_params = $q->param('return_params');
    my @return_params_hidden = ();
    while (my ($k, $v) = each(%return_params)) {
        push(@return_params_hidden, $q->hidden(-name => $k,
                                                       -value => $v,
                                                       -override=>1));
    }
    $tmpl_data{return_params} = join("\n", @return_params_hidden);

    $tmpl_data{can_edit} = 1 unless ( $m->checked_out and ($m->checked_out_by ne $session{user_id}) );

    # Send data back to caller for inclusion in template
    return \%tmpl_data;
}


# Given an array of parameter names, return HTML hidden
# input fields suitible for setting up a return link
sub make_return_params {
    my $self = shift;
    my @return_param_list = ( @_ );

    my $q = $self->query();

    my @return_params_hidden = ();
    foreach my $hrp (@return_param_list) {
        # Store param name
        push(@return_params_hidden, $q->hidden(-name => 'return_params',
                                                       -value => $hrp,
                                                       -override => 1));

        # Store param value
        my $pval = $q->param($hrp);
        $pval = '' unless (defined($pval));
        push(@return_params_hidden, $q->hidden(-name => 'return_params',
                                                       -value => $pval,
                                                       -override => 1));
    }

    my $return_params = join("\n", @return_params_hidden);
    return $return_params;
}


# Given a persist_vars and find_params, return the pager object
sub make_pager {
    my $self = shift;
    my ($persist_vars, $find_params, $show_thumbnails) = @_;

    my @columns = qw(
                     pub_status 
                     media_id 
                     thumbnail
                     url
                     title 
                     creation_date
                     commands_column
                     checkbox_column
                    );

    my %column_labels = ( 
                         pub_status => '',
                         media_id => 'ID',
                         thumbnail => 'Thumbnail',
                         url => 'URL',
                         commands_column => '',
                         title => 'Title',
                         creation_date => 'Date',
                        );

    # Hide thumbnails
    unless ($show_thumbnails) {
        splice(@columns, 2, 1);
        delete($column_labels{thumbnail});
    }

    my $q = $self->query();
    my $pager = Krang::HTMLPager->new(
                                      cgi_query => $q,
                                      persist_vars => $persist_vars,
                                      use_module => 'Krang::Media',
                                      find_params => $find_params,
                                      columns => \@columns,
                                      column_labels => \%column_labels,
                                      columns_sortable => [qw( media_id url title creation_date )],
                                      row_handler => sub { $self->find_media_row_handler($show_thumbnails, @_); },
                                      id_handler => sub { return $_[0]->media_id },
                                     );

    return $pager;
}


# Pager row handler for media find run-modes
sub find_media_row_handler {
    my $self = shift;
    my ($show_thumbnails, $row, $media) = @_;

    # media_id
    my $media_id = $media->media_id();
    $row->{media_id} = $media_id;

    # format url to fit on the screen and to link to preview
    $row->{url} = format_url( url => $media->url(),
                              linkto => "javascript:preview_media('". $media_id ."')" );

    # title
    $row->{title} = $media->title();

    # thumbnail
    if ($show_thumbnails) {
        my $thumbnail_path = $media->thumbnail_path(relative => 1) || '';
        $row->{thumbnail} = "<a href='javascript:preview_media($media_id)'><img src=\"$thumbnail_path\" border=0></a>";
    }

    # creation_date
    my $tp = $media->creation_date();
    $row->{creation_date} = (ref($tp)) ? $tp->strftime('%b %e, %Y %l:%M %p') : '[n/a]';

    # pub_status
    my $pub_status = ($media->published()) ? 'P' : '&nbsp;' ;
    $row->{pub_status} = '&nbsp;<b>'. $pub_status .'</b>&nbsp;';

    if (($media->checked_out) and ($media->checked_out_by ne $session{user_id})) {
        $row->{commands_column} = '<a href="javascript:view_media('."'".$media->media_id."'".')">View</a>'
    } else {
        $row->{commands_column} = '<a href="javascript:edit_media('."'".$media->media_id."'".')">Edit</a>'
        . '&nbsp;|&nbsp;'
        . '<a href="javascript:view_media('."'".$media->media_id."'".')">View</a>'
    }

}


# Actually save the media.  Catch exceptions
# Return error hash if errors are encountered
sub do_save_media {
    my $self = shift;
    my $m = shift;

    # Attempt to write back to database
    eval { $m->save() };

    # Is it a dup?
    if ($@) {
        if (ref($@) and $@->isa('Krang::Media::DuplicateURL')) {
            add_message('duplicate_url');
            return (duplicate_url=>1);
        } else {
            # Not our error!
            die($@);
        }
    }

    # If everything is OK, rturn an empty array
    return ();
}




1;


=back

=cut



####  Created by:  ######################################
#
#
# use CGI::Application::Generator;
# my $c = CGI::Application::Generator->new();
# $c->app_module_tmpl($ENV{HOME}.'/krang/templates/krang_cgi_app.tmpl');
# $c->package_name('Krang::CGI::Media');
# $c->base_module('Krang::CGI');
# $c->start_mode('add');
# $c->run_modes(qw(
#                  find
#                  advanced_find
#                  add
#                  save_add
#                  cancel_add
#                  save_stay_add
#                  edit
#                  save_edit
#                  save_stay_edit
#                  delete
#                  delete_selected
#                  view
#                  view_version
#                  revert_version
#                 ));
# $c->use_modules(qw/Krang::Category Krang::Media Krang::Widget Krang::Message Krang::HTMLPager Krang::Pref Krang::Session Carp/);
# $c->tmpl_path('Media/');
# print $c->output_app_module();
