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


use Krang::Media;
use Krang::Widget qw(category_chooser date_chooser decode_date format_url);
use Krang::Message qw(add_message);
use Krang::HTMLPager;
use Krang::Pref;
use Krang::Session qw(%session);
use Carp qw(croak);


use constant WORKSPACE_URL => '/workspace.pl';


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
                         save_stay_add
                         edit
                         save_edit
                         save_stay_edit
                         delete
                         delete_selected
                         save_and_associate_media
                         view
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

    my $search_creation_date = decode_date(
                                           query => $q,
                                           name => 'search_creation_date',
                                          );
    if ($search_creation_date) {
        # If date is valid send it to search and persist it.
        $find_params->{creation_date} = $search_creation_date;
        for (qw/day month year/) {
            my $varname = "search_creation_date_$_";
            $persist_vars->{$varname} = $q->param($varname);
        }
    } else {
        # Delete date chooser if date is incomplete
        for (qw/day month year/) {
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

    # search_has_attributes
    my $search_has_attributes = $q->param('search_has_attributes');
    if ($search_has_attributes) {
        $find_params->{has_attributes} = $search_has_attributes;
        $persist_vars->{search_has_attributes} = $search_has_attributes;
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
    $t->param(date_chooser => date_chooser(
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

    # Save object to database and checkout to Workspace
    $m->save();
    $m->checkout();

    # Notify user
    add_message("new_media_saved");

    # Redirect to workspace.pl
    my $url = '/workspace.pl';
    $self->header_props(-url=>$url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
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
    my $workspace_url = WORKSPACE_URL;
    $self->header_props(-url=>$workspace_url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$workspace_url\">$workspace_url</a>";
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

    # Save object to database and checkout to Workspace
    $m->save();
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
    my $m;
    if ($media_id) {
        # If we have a media_id, force load using it.
        ($m) = Krang::Media->find(media_id=>$media_id);
        $session{media} = $m;
    } else {
        # Otherwise, expect to have a media object in the session
        $m = $session{media};
    }
    die ("Can't find media object with media_id '$media_id'") unless (ref($m));

    my $t = $self->load_tmpl('edit_media.tmpl', associate=>$q);

    my $media_tmpl_data = $self->make_media_tmpl_data($m);
    $t->param($media_tmpl_data);

    # Propagate messages, if we have any
    $t->param(%args) if (%args);

    return $t->output();
}





=item save_edit

Description of run-mode 'save_edit'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


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

    # Save object to database and checkout to Workspace
    $m->save();
    $m->checkout();

    # Notify user
    add_message("media_saved");

    # Redirect to workspace.pl
    my $url = '/workspace.pl';
    $self->header_props(-url=>$url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}





=item save_stay_edit

Description of run-mode 'save_stay_edit'...

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
    my $workspace_url = WORKSPACE_URL;
    $self->header_props(-url=>$workspace_url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$workspace_url\">$workspace_url</a>";
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
    $self->header_props(-url=>$url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}





=item view

Description of run-mode 'view'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub view {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
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


# Update the provided Media object with data from the CGI form\
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

            next;
        }

        # Default: Grab scalar value from CGI form
        $m->$mf( $q->param($mf) );
    }
}


# Given a media object, $m, return a hashref with all the data needed
# for the edit template.
sub make_media_tmpl_data {
    my $self = shift;
    my $m = shift;

    my $q = $self->query();
    my %tmpl_data = ();

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

    # Build upload field
    my $upload_chooser = $q->filefield(
                                       -name => 'media_file',
                                       -size => 32,
                                      );
    $tmpl_data{upload_chooser} = $upload_chooser;

    # If we have a filename, show it.
    $tmpl_data{file_size} = sprintf("%.1f", ($m->file_size() / 1024))
      if ($tmpl_data{filename}  = $m->filename());

    # Set up details only found on edit (not add) view
    if ($tmpl_data{media_id} = $m->media_id()) {
        my $thumbnail_path = $m->thumbnail_path(relative => 1) || '';
        $tmpl_data{thumbnail_path} = $thumbnail_path;
    }

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

    # Send data back to caller for inclusion in template
    return \%tmpl_data;
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
                     command_column 
                     checkbox_column
                    );

    my %column_labels = ( 
                         pub_status => '',
                         media_id => 'ID',
                         thumbnail => 'Thumbnail',
                         url => 'URL',
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
                                      command_column_commands => [qw( edit_media view_media )],
                                      command_column_labels => {
                                                                edit_media     => 'Edit',
                                                                view_media     => 'View',
                                                               },
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
        $row->{thumbnail} = "<img src=\"$thumbnail_path\">";
    }

    # creation_date
    my $tp = $media->creation_date();
    $row->{creation_date} = (ref($tp)) ? $tp->mdy('/') : '[n/a]';

    # pub_status  -- NOT YET IMPLEMENTED
    $row->{pub_status} = '&nbsp;<b>P</b>&nbsp;';

}




1;


=back


=head1 AUTHOR

Author of Module <author@module>


=head1 SEE ALSO

L<Krang::Media>, L<Krang::Widget>, L<Krang::Message>, L<Krang::HTMLPager>, L<Krang::Pref>, L<Krang::Session>, L<Carp>, L<Krang::CGI>

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
#                 ));
# $c->use_modules(qw/Krang::Media Krang::Widget Krang::Message Krang::HTMLPager Krang::Pref Krang::Session Carp/);
# $c->tmpl_path('Media/');
# print $c->output_app_module();
