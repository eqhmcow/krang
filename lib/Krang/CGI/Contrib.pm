package Krang::CGI::Contrib;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base         => qw(CGI);
use Krang::ClassLoader Localization => qw(localize);
use Krang::ClassLoader Widget       => qw(category_chooser date_chooser decode_date format_url);
use strict;
use warnings;

=head1 NAME

Krang::CGI::Contrib - web interface to manage Contributors


=head1 SYNOPSIS

  use Krang::ClassLoader 'CGI::Contrib';
  my $app = pkg('CGI::Contrib')->new();
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

use Krang::ClassLoader 'Contrib';
use Krang::ClassLoader 'Conf';
use Krang::ClassLoader 'Group';
use Krang::ClassLoader Message => qw(add_message add_alert);
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Widget  => qw(autocomplete_values);
use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';

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

    $self->run_modes(
        [
            qw(
              search
              associate_story
              associate_media
              associate_search
              associate_selected
              unassociate_selected
              reorder_contribs
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
              autocomplete
              save_and_find_media_link
              find_media_link
              select_media
              )
        ]
    );

    $self->tmpl_path('Contrib/');

}

##############################
#####  RUN-MODE METHODS  #####
##############################

=item search

Display a list of matching contributors, or all
contributors if no filter text is provided.

This run-mode expects an optional parameters "search_filter"
which is expected to contain the text string which is used to 
query contributors.

=cut

sub search {
    my $self = shift;

    my $q = $self->query();

    # Shunt to associate_search if we're in associate mode
    return $self->associate_search() if ($q->param('associate_mode'));

    my $t = $self->load_tmpl("list_view.tmpl", associate => $q, loop_context_vars => 1);

    # Do simple search based on search field
    my $search_filter = $q->param('search_filter');
    if (!defined $search_filter) {
        $search_filter = $session{KRANG_PERSIST}{pkg('Contrib')}{search_filter}
          || '';
    }

    # We need order_by count when counting based on contrib type
    my $order_by = $q->param('krang_pager_sort_field')
      if $q->param('krang_pager_sort_field')
          and $q->param('krang_pager_sort_field') eq 'type';

    # Configure pager
    my $pager = pkg('HTMLPager')->new(
        cgi_query    => $q,
        persist_vars => {
            rm            => 'search',
            search_filter => $search_filter,
        },
        use_module  => pkg('Contrib'),
        find_params => {
            simple_search => $search_filter,
            order_by      => $order_by
        },
        columns       => [qw(last first_middle type command_column checkbox_column)],
        column_labels => {
            last         => 'Last Name',
            first_middle => 'First, Middle Name',
            type         => 'Type',
        },
        columns_sortable        => [qw( last first_middle type )],
        columns_sort_map        => {first_middle => 'first,middle'},
        command_column_commands => [qw( edit_contrib )],
        command_column_labels   => {edit_contrib => 'Edit'},
        row_handler             => sub { $self->list_view_contrib_row_handler(@_) },
        id_handler              => sub { return $_[0]->contrib_id },
    );

    # Fill the template
    $t->param(
        pager_html    => $pager->output(),
        row_count     => $pager->row_count(),
        search_filter => $search_filter,
    );

    # Propagate other params

    return $t->output();
}

=item associate_story

Invoked by direct link from Krang::CGI::Story, 
this run-mode provides an entry point through which
Contributors may be associated with Story objects.

It is expected that the story object with which we
are to associate contributors be available via the 
%session in the key 'story'.

When the user clicks "save" or "cancel" they will be
returned to the "edit" run-mode of Krang::CGI::Story, e.g.:

  http://server/story.pl?rm=edit

=cut

sub associate_story {
    my $self = shift;

    $self->query->param(associate_mode => 'story');
    return $self->search();
}

=item associate_media

Invoked by direct link from Krang::CGI::Media, 
this run-mode provides an entry point through which
Contributors may be associated with Media objects.

It is expected that the media object with which we
are to associate contributors be available via the 
%session in the key 'media'.

When the user clicks "save" or "cancel" they will be
returned to the "edit" run-mode of Krang::CGI::Media, e.g.:

  http://server/media.pl?rm=edit

=cut

sub associate_media {
    my $self = shift;

    $self->query->param(associate_mode => 'media');
    return $self->search();
}

=item associate_search

This run-mode is activated in place of run-mode "search"
when CGI parameter "associate_mode" is set.  It builds
the "edit contributors" screen, which contains a search
interface, as well as a means to add or remove contributors
from either media or story objects.

This run-mode expects the parameter "associate_mode" to 
exist in the query, and for it to contain either "story"
or "media".  It also expects that a story or media object
will be stored in the %session in a key "story" or "media",
respectively.

=cut

sub associate_search {
    my $self        = shift;
    my %ui_messages = (@_);

    my $q = $self->query();

    # Get media or story object from session -- or die() trying
    my $ass_obj = $self->get_ass_obj();

    my $t = $self->load_tmpl("associate_list_view.tmpl", associate => $q, loop_context_vars => 1);
    $t->param(%ui_messages) if (%ui_messages);

    # Set Boolean for H::T
    my $associate_mode = $q->param('associate_mode');
    $t->param(associate_story => ($associate_mode eq 'story'));

    # Get table of contrib types
    my %contrib_types = pkg('Pref')->get('contrib_type');

    # Localize contrib_types
    %contrib_types = map { $_ => localize($contrib_types{$_}) } keys %contrib_types;

    # Build up list of currently associated contributors
    my @contribs = $ass_obj->contribs();

    # Set up vars for re-order drop-down
    my $ass_contrib_count = scalar(@contribs);
    my $curr_contrib_pos  = 0;

    my @associated_contributors_loop = ();
    my %associated_contrib_filter    = ();
    foreach my $c (@contribs) {
        my $contrib_id      = $c->contrib_id();
        my $contrib_type_id = $c->selected_contrib_type();

        # Create entry in filter list
        $associated_contrib_filter{$contrib_id} = {
            contrib_id         => $contrib_id,
            available_type_ids => [$c->contrib_type_ids()],
          }
          unless (exists($associated_contrib_filter{$contrib_id}));

        # Remove available type from associated_contrib_filter
        $associated_contrib_filter{$contrib_id}->{'available_type_ids'} =
          [grep { $_ ne $contrib_type_id }
              @{$associated_contrib_filter{$contrib_id}->{'available_type_ids'}}];

        # Make re-order drop-down for this contrib
        my $associated_contrib_id_type = sprintf("%d:%d", $c->contrib_id, $contrib_type_id);
        my $order_contrib_popup_menu = $q->popup_menu(
            -name     => 'order_contrib_' . $associated_contrib_id_type,
            -onChange => "Krang.update_order(this, 'order_contrib_')",
            -values   => [(1 .. $ass_contrib_count)],
            -default  => ++$curr_contrib_pos,
            -override => 1,
        );

        # Propagate to template loop
        push(
            @associated_contributors_loop,
            {
                contrib_id               => $contrib_id,
                contrib_type_id          => $contrib_type_id,
                type                     => $contrib_types{$contrib_type_id},
                first                    => $c->first(),
                middle                   => $c->middle(),
                last                     => $c->last(),
                order_contrib_popup_menu => $order_contrib_popup_menu,
            }
        );
    }

    # Propagate list of current contributors
    $t->param(associated_contributors => \@associated_contributors_loop);

    # Do simple search based on search field
    my $search_filter = $q->param('search_filter') || '';
    my @exclude_contrib_ids = (
        grep { not(@{$associated_contrib_filter{$_}->{'available_type_ids'}}); }
          keys(%associated_contrib_filter)
    );

    # Make pager
    my $pager = pkg('HTMLPager')->new(
        cgi_query    => $q,
        persist_vars => {
            rm             => 'associate_search',
            search_filter  => $search_filter,
            associate_mode => $associate_mode,
        },
        use_module  => pkg('Contrib'),
        find_params => {
            simple_search       => $search_filter,
            exclude_contrib_ids => \@exclude_contrib_ids,
        },
        columns       => [qw(last first_middle type checkbox_column)],
        column_labels => {
            last         => 'Last Name',
            first_middle => 'First, Middle Name',
            type         => 'Type',
        },
        columns_sortable => [qw( last first_middle )],
        columns_sort_map => {first_middle => 'first,middle'},
        row_handler      => sub {
            $self->list_view_ass_contrib_row_handler(@_, \%associated_contrib_filter,
                \%contrib_types,);
        },
        id_handler => sub {
            return 0;
        },
    );

    # Determine if user should see 'Add Contributor' button
    my %admin_perms = pkg('Group')->user_admin_permissions();
    $t->param('user_can_add_contributors' => $admin_perms{admin_contribs});

    # Put pager in template
    $pager->fill_template($t);
    $t->param('row_count', $pager->row_count());

    return $t->output();
}

=item associate_selected

Remove the selected contributors from the current story or
media object.  Return to associate_search mode.

This run-mode expects the parameter "associate_mode" to 
exist in the query, and for it to contain either "story"
or "media".  It also expects that a story or media object
will be stored in the %session in a key "story" or "media",
respectively.

=cut

sub associate_selected {
    my $self = shift;

    my $q                      = $self->query();
    my @contrib_associate_list = ($q->param('krang_pager_rows_checked'));

    unless (@contrib_associate_list) {
        add_alert('missing_contrib_associate_list');
        return $self->associate_search();
    }

    # Get media or story object from session -- or die() trying
    my $ass_obj = $self->get_ass_obj();

    # Get list of current contributors -- we have to append to this list
    my @current_contribs = ($ass_obj->contribs());

    # Unfortunately, there is no add_contrib() method.  We have to re-add the whole list
    # Worse, we can't mix objects and IDs via the contribs() method.  Must choose one or
    # the other.  Fastest way is to flatten to IDs
    my @new_contribs =
      (map { {contrib_id => $_->contrib_id(), contrib_type_id => $_->selected_contrib_type(),} }
          @current_contribs);

    # Append selected contrbutors and types to end of list
    foreach my $ct_ids (@contrib_associate_list) {
        my ($contrib_id, $contrib_type_id) = split(/:/, $ct_ids);

        # Verify data "looks" right
        die("Invalid new contrib_id '$contrib_id', contrib_type_id '$contrib_type_id'")
          unless (($contrib_id =~ /^\d+$/) && ($contrib_type_id =~ /^\d+$/));

        push(
            @new_contribs,
            {
                contrib_id      => $contrib_id,
                contrib_type_id => $contrib_type_id,
            }
        );
    }

    # Update list of contribs in story or media object
    $ass_obj->contribs(@new_contribs);

    add_message('message_selected_associated');
    return $self->associate_search();
}

=item unassociate_selected

Remove the selected contributors from the current story or
media object.  Return to associate_search.

This run-mode expects the parameter "associate_mode" to 
exist in the query, and for it to contain either "story"
or "media".  It also expects that a story or media object
will be stored in the %session in a key "story" or "media",
respectively.

=cut

sub unassociate_selected {
    my $self = shift;

    my $q                        = $self->query();
    my @contrib_unassociate_list = ($q->param('contrib_unassociate_list'));

    unless (@contrib_unassociate_list) {
        add_alert('missing_contrib_unassociate_list');
        return $self->associate_search();
    }

    # Get media or story object from session -- or die() trying
    my $ass_obj = $self->get_ass_obj();

    # Build up list of contribs, skipping over contribs who are in @contrib_unassociate_list
    my @new_contribs = ();
    foreach my $contrib ($ass_obj->contribs()) {
        my $curr_contrib_id_type_str =
          sprintf("%d:%d", $contrib->contrib_id(), $contrib->selected_contrib_type());

        # Skip contribs who are on remove list
        next if (grep { $_ eq $curr_contrib_id_type_str } @contrib_unassociate_list);

        # No match on remove list?  Propagate contrib back to list
        push(@new_contribs, $contrib);
    }

    if (@new_contribs) {

        # Update list of contribs in story or media object
        $ass_obj->contribs(@new_contribs);
    } else {

        # No contribs left -- force clear list
        $ass_obj->clear_contribs();
    }

    add_message('message_selected_unassociated');
    return $self->associate_search();
}

=item reorder_contribs

Reorder the contributors associated with the current story or
media object.  Return to associate_search.

This run-mode expects the parameter "associate_mode" to 
exist in the query, and for it to contain either "story"
or "media".  It also expects that a story or media object
will be stored in the %session in a key "story" or "media",
respectively.

=cut

sub reorder_contribs {
    my $self = shift;

    my $q = $self->query();

    # Get media or story object from session -- or die() trying
    my $ass_obj = $self->get_ass_obj();

    # Get params related to re-ordering
    my @reorder_params = (grep { /^order\_contrib\_\d+\:\d+$/ } ($q->param()));

    # Build up a sorted list of contribs
    my @ordered_contrib_params = (sort { $q->param($a) <=> $q->param($b) } @reorder_params);

    # Update the $ass_obj with the new sorted contribs list
    my @ordered_contribs = ();
    foreach my $contrib_param (@ordered_contrib_params) {
        $contrib_param =~ /^order\_contrib\_(\d+)\:(\d+)$/;
        my $contrib_id      = $1;
        my $contrib_type_id = $2;
        push(
            @ordered_contribs,
            {
                contrib_id      => $contrib_id,
                contrib_type_id => $contrib_type_id,
            }
        );
    }
    $ass_obj->contribs(@ordered_contribs);

    add_message('message_contribs_reordered');
    return $self->associate_search();
}

=item delete_selected

Delete a set of contribuitors, specified by check-mark
on the "Contributor List" screen provided by the "search" 
run-mode.  Return to the "search" run-mode.

This mode expects the query param "krang_pager_rows_checked"
to contain an array of contrib_id values which correspond
to contributor records to be deleted.

=cut

sub delete_selected {
    my $self = shift;

    my $q                   = $self->query();
    my @contrib_delete_list = ($q->param('krang_pager_rows_checked'));
    $q->delete('krang_pager_rows_checked');

    # No selected contribs?  Just return to list view without any message
    return $self->search() unless (@contrib_delete_list);

    foreach my $cid (@contrib_delete_list) {
        pkg('Contrib')->delete($cid);
    }

    add_message('message_selected_deleted');
    return $self->search();
}

=item add

Display an "Add Contributor" screen, through which
users may create a new Contributor object.

=cut

sub add {
    my $self        = shift;
    my %ui_messages = (@_);

    my $q = $self->query();
    my $t = $self->load_tmpl("edit_view.tmpl", associate => $q);
    $t->param(add_mode => 1);
    $t->param(%ui_messages) if (%ui_messages);

    # Make new Contrib, but don't save it
    my $c = pkg('Contrib')->new();

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

    my %errors = ($self->validate_contrib());

    # Return to add screen if we have errors
    return $self->add(%errors) if (%errors);

    # Retrieve new contrib object
    my $c = $session{EDIT_CONTRIB} || 0;
    die("Can't retrieve EDIT_CONTRIB from session") unless (ref($c));

    my %save_errors = ($self->do_update_contrib($c));
    return $self->add(%save_errors) if (%save_errors);

    $q->delete(keys(%{&CONTRIB_PROTOTYPE}));

    # Are we in associate_mode?  If so, this contributor should be automagically 
    # attached to $ass_obj.
    if ($q->param('associate_mode')) {

        # Build up list for each contrib_id/type_id combo
        my $contrib_id             = $c->contrib_id();
        my @contrib_type_ids       = ($c->contrib_type_ids());
        my @contrib_associate_list = (map { sprintf("%d:%d", $contrib_id, $_) } @contrib_type_ids);

        # Add param for "associate_selected" run-mode
        $q->param(krang_pager_rows_checked => @contrib_associate_list);

        # Jump to associate_selected mode -- do the associate
        return $self->associate_selected();
    }

    add_message('message_contrib_added');
    return $self->search();
}

=item cancel_add

Cancel the addition of a Contributor object which was specified on the 
"Add Contributor" screen.  Return to the "search" run-mode.

=cut

sub cancel_add {
    my $self = shift;

    my $q = $self->query();
    $q->delete(keys(%{&CONTRIB_PROTOTYPE}));

    add_message('message_add_cancelled');
    return $self->search();
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

    my %errors = ($self->validate_contrib());

    # Return to add screen if we have errors
    return $self->add(%errors) if (%errors);

    # Retrieve new contrib object
    my $c = $session{EDIT_CONTRIB} || 0;
    die("Can't retrieve EDIT_CONTRIB from session") unless (ref($c));

    my %save_errors = ($self->do_update_contrib($c));
    return $self->add(%save_errors) if (%save_errors);

    # Set up for edit mode
    my $contrib_id = $c->contrib_id();
    $q->delete(keys(%{&CONTRIB_PROTOTYPE}));
    $q->param(contrib_id => $contrib_id);
    $q->param(rm         => 'edit');

    add_message('message_contrib_added');
    return $self->edit();
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
    my ($self, %ui_messages) = @_;
    my $q = $self->query();

    my ($c, $contrib_id);
    # look in query string else pull from session
    if( $q->param('contrib_id' ) ) {
        $contrib_id = $q->param('contrib_id');
        ($c) = pkg('Contrib')->find(contrib_id => $contrib_id);
    } elsif( $session{EDIT_CONTRIB}) {
        $c = $session{EDIT_CONTRIB};
        $contrib_id = $c->contrib_id;
    } else {
        die 'No contrib present in query or session!"';
    }

    # Did we get our contributor?  Presumbably, users get here from a list.  IOW, there is
    # no valid (non-fatal) case where a user would be here with an invalid contrib_id
    die("No such contrib_id '$contrib_id'") unless $c;

    # Stash it in the session for later
    $session{EDIT_CONTRIB} = $c;

    my $t = $self->load_tmpl("edit_view.tmpl", associate => $q);
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

    my %errors = ($self->validate_contrib());

    # Return to edit screen if we have errors
    return $self->edit(%errors) if (%errors);

    # Retrieve new contrib object
    my $c = $session{EDIT_CONTRIB} || 0;
    die("Can't retrieve EDIT_CONTRIB from session") unless (ref($c));

    my %save_errors = ($self->do_update_contrib($c));
    return $self->edit(%save_errors) if (%save_errors);

    $q->delete(keys(%{&CONTRIB_PROTOTYPE}));

    add_message('message_contrib_saved');
    return $self->search();
}

=item cancel_edit

Cancel the edit of the Contributor object currently on the 
"Edit Contributor" screen.  Return to the "search" run-mode.

=cut

sub cancel_edit {
    my $self = shift;

    my $q = $self->query();
    $q->delete(keys(%{&CONTRIB_PROTOTYPE}));

    add_message('message_save_cancelled');
    return $self->search();
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

    # Return to edit screen if we have errors
    my %errors = ($self->validate_contrib());
    return $self->edit(%errors) if (%errors);

    # Retrieve new contrib object
    my $c = $session{EDIT_CONTRIB};
    die("Can't retrieve EDIT_CONTRIB from session") unless $c && ref $c;
    my %save_errors = $self->do_update_contrib($c);
    return $self->edit(%save_errors) if %save_errors;

    # Set up for edit mode
    my $contrib_id = $c->contrib_id();
    $q->delete(keys(%{&CONTRIB_PROTOTYPE}));
    $q->param(contrib_id => $contrib_id);
    $q->param(rm         => 'edit');

    add_message('message_contrib_saved');
    return $self->edit();
}

sub save_and_find_media_link {
    my $self = shift;
    my $q = $self->query;

    # Return to edit screen if we have errors
    my %errors = ($self->validate_contrib());
    return $self->edit(%errors) if (%errors);

    # Retrieve new contrib object and do the actual save
    my $c = $session{EDIT_CONTRIB};
    die("Can't retrieve EDIT_CONTRIB from session") unless $c && ref $c;
    my %save_errors = $self->do_update_contrib($c, 1);
    return $self->edit(%save_errors) if %save_errors;

    # delete anything that might cause problems
    $q->delete(
        keys %{&CONTRIB_PROTOTYPE},  'krang_pager_sort_field',
        'krang_pager_curr_page_num', 'krang_pager_show_big_view',
        'krang_pager_sort_order_desc'
    );

    return $self->find_media_link();
}

sub find_media_link {
    my ($self, %args) = @_;
    my $q    = $self->query();
    my $tmpl = $self->load_tmpl('find_media_link.tmpl', associate => $q);
    my $adv  = $q->param('advanced') ? 1 : 0; 

    # determine appropriate find params for search
    my %find = (may_see => 1);
    my %persist = (
        rm         => 'find_media_link',
        advanced   => $adv,
    );
    if ($adv) {
        my $search_below_category_id = $q->param('search_below_category_id');
        if ($search_below_category_id) {
            $persist{search_below_category_id} = $search_below_category_id;
            $find{below_category_id}           = $search_below_category_id;
        }

        my $search_creation_date = decode_date(
            query => $q,
            name  => 'search_creation_date'
        );
        if ($search_creation_date) {

            # If date is valid send it to search and persist it.
            $find{creation_date} = $search_creation_date;
            for (qw/day month year/) {
                my $varname = "search_creation_date_$_";
                $persist{$varname} = $q->param($varname);
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
            $find{filename_like}      = "\%$search_filename\%";
            $persist{search_filename} = $search_filename;
        }

        # search_title
        my $search_title = $q->param('search_title');
        if ($search_title) {
            $search_title =~ s/\W+/\%/g;
            $find{title_like}      = "\%$search_title\%";
            $persist{search_title} = $search_title;
        }

        # search_media_id
        my $search_media_id = $q->param('search_media_id');
        if ($search_media_id) {
            $find{media_id}           = $search_media_id;
            $persist{search_media_id} = $search_media_id;
        }

        # search_no_attributes
        my $search_no_attributes = $q->param('search_no_attributes');
        if ($search_no_attributes) {
            $find{no_attributes}           = $search_no_attributes;
            $persist{search_no_attributes} = $search_no_attributes;
        }

        $tmpl->param(
            category_chooser =>
              scalar category_chooser(query => $q, name => 'search_below_category_id'),
            date_chooser =>
              date_chooser(query => $q, name => 'search_creation_date', nochoice => 1),
        );

    } else {
        my $search_filter =
          defined($q->param('search_filter'))
          ? $q->param('search_filter')
          : $session{KRANG_PERSIST}{pkg('Contrib')}{find_media}{search_filter};
        %find    = (simple_search => $search_filter);
        $persist{search_filter} = $search_filter;
        $tmpl->param(search_filter => $search_filter);
    }

    my $pager = pkg('HTMLPager')->new(
        cgi_query    => $q,
        persist_vars => \%persist,
        use_module  => pkg('Media'),
        cache_key   => pkg('Contrib') . '-find_media',
        find_params => \%find,
        columns     => [
            qw(
              pub_status
              media_id
              thumbnail
              url
              creation_date
              command_column
              )
        ],
        column_labels => {
            pub_status    => '',
            media_id      => 'ID',
            thumbnail     => '',
            url           => 'URL',
            creation_date => 'Date',
        },
        columns_sortable        => [qw( media_id url creation_date )],
        command_column_commands => [qw( select_media )],
        command_column_labels   => {select_media => 'Select',},
        row_handler             => sub { $self->_find_media_link_row_handler(@_) },
        id_handler              => sub { shift->media_id },
    );
    $tmpl->param(
        pager_html => $pager->output,
        advanced   => $adv,
    );

    return $tmpl->output;
}

sub select_media {
    my $self  = shift;
    my $q = $self->query;
    my $media_id = $q->param('selected_media_id');

    # find media and set it in element data
    my ($media) = pkg('Media')->find(media_id => $media_id);
    my $c = $session{EDIT_CONTRIB};
    die("Can't retrieve EDIT_CONTRIB from session") unless $c && ref $c;
    $c->image($media);

    add_message('selected_media', id => $media_id);

    return $self->edit;
}


# Pager row handler for media find run-mode
sub _find_media_link_row_handler {
    my ($self, $row, $media, $pager) = @_;
    my $id = $media->media_id;
    $row->{media_id} = $id;

    # format url to fit on the screen and to link to preview
    $row->{url} = format_url(
        url     => $media->url,
        class   => 'media-preview-link',
        name    => "media_$id",
        length  => 60,
    );

    # thumbnail if we have it
    my $thumbnail_path = $media->thumbnail_path(relative => 1);
    if ($thumbnail_path) {
        $row->{thumbnail} = qq|
           <a href="" class="media-preview-link" name="media_$id">
              <img alt="" src="$thumbnail_path" class="thumbnail">
           </a>
        |;
    } else {
        $row->{thumbnail} = "&nbsp;";
    }

    my $tp = $media->creation_date();
    $row->{creation_date} = $tp ? $tp->strftime(localize('%m/%d/%Y')) : localize('[n/a]');
    $row->{pub_status} = $media->published ? '<b>' . localize('P') . '</b>' : '&nbsp;';
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

    my $q          = $self->query();
    my $contrib_id = $q->param('contrib_id');

    # Check the session.  Is this contrib stashed there?  (Clean, if so.)
    my $c = $session{EDIT_CONTRIB} || 0;
    if (ref($c) && (($c->contrib_id() || '') eq $contrib_id)) {

        # Delete contrib and clear from session
        $c->delete();
        delete($session{EDIT_CONTRIB});
    } else {

        # Delete this contrib by contrib_id
        pkg('Contrib')->delete($contrib_id);
    }

    add_message('message_contrib_deleted');
    return $self->search();
} 
#############################
#####  PRIVATE METHODS  #####
#############################

# Set up special row_handler for associate contrib screen
sub list_view_ass_contrib_row_handler {
    my $self = shift;
    my $q    = $self->query;
    my ($row_hashref, $contrib, $pager, $associated_contrib_filter, $contrib_type_prefs) = @_;

    $row_hashref->{first_middle} = $contrib->first;
    $row_hashref->{first_middle} .= ' ' . $contrib->middle if $contrib->middle;
    $row_hashref->{last} = $contrib->last;

    # 'type' isn't actually used.  Loop 'contrib_types' instead
    delete($row_hashref->{type});

    # Get rid of checkbox_column.  We're rolling our own.
    delete($row_hashref->{checkbox_column});

    # State for contrib
    my $contrib_id = $contrib->contrib_id();
    my $contrib_filter = $associated_contrib_filter->{$contrib_id} || 0;

    # Now build up types loop 'contrib_types'
    my @contrib_type_ids = ($contrib->contrib_type_ids());
    @contrib_type_ids = (@{$contrib_filter->{available_type_ids}}) if (ref($contrib_filter));
    my $contrib_type_count = scalar(@contrib_type_ids);

    my @contrib_types = ();
    foreach my $contrib_type_id (@contrib_type_ids) {
        push(
            @contrib_types,
            {
                contrib_id      => $contrib_id,
                contrib_type_id => $contrib_type_id,
                type            => $contrib_type_prefs->{$contrib_type_id},
            }
        );
    }
    $row_hashref->{contrib_types} = \@contrib_types;

    # Add contrib_row_span for rowspan
    $row_hashref->{contrib_type_count} = $contrib_type_count;
}

# Krang::HTMLPager row handler for contrib list view
sub list_view_contrib_row_handler {
    my ($self, $row_hashref, $contrib, $pager) = @_;
    my $q = $self->query;
    $row_hashref->{first_middle} = $q->escapeHTML($contrib->first);
    $row_hashref->{first_middle} .= '&nbsp;' . $q->escapeHTML($contrib->middle)
      if ($contrib->middle());
    $row_hashref->{last} = $q->escapeHTML($contrib->last);
    $row_hashref->{type} =
      join(',&nbsp;', $q->escapeHTML(map { localize($_) } $contrib->contrib_type_names));
}

# Get the media or story object from session or die() trying
sub get_ass_obj {
    my $self      = shift;
    my $q         = $self->query();
    my $mode      = $q->param('associate_mode') || '';
    my $edit_uuid = $q->param('edit_uuid');

    # validate for "associate_mode".
    die("Invalid associate_mode '$mode'") unless (grep { $mode eq $_ } qw( story media ));

    # Get media or story object from session -- or die() trying
    my $obj;
    if ($mode eq 'story') {
        $obj = $self->get_session_story_obj($edit_uuid);
    } elsif ($mode eq 'media') {
        $obj = $self->get_session_media_obj($edit_uuid);
    }
    die("No story or media object available for contributor association") unless $obj;
    return $obj;
}

# Updated the provided Contrib object with data
# from the CGI query
sub do_update_contrib {
    my ($self, $contrib, $dont_save) = @_;
    my $q = $self->query();

    # Get prototype for the purpose of update
    my %contrib_prototype = (%{&CONTRIB_PROTOTYPE});

    # We can't update contrib_id
    delete($contrib_prototype{contrib_id});

    # contrib_type_ids is a special case
    # delete($contrib_prototype{contrib_type_ids});

    # Grab each CGI query param and set the corresponding Krang::Contrib property
    foreach my $ck (keys(%contrib_prototype)) {

        # Presumably, query data is already validated and un-tainted
        $contrib->$ck($q->param($ck));
    }

    my $media = $self->upload_image($contrib);

    $contrib->image($media) if defined($media);

    # Attempt to write back to database
    eval { $contrib->save() } unless $dont_save;

    # Is it a dup?
    if ($@) {

        # delete the media object if it exists

        if (ref($@) and $@->isa('Krang::Contrib::DuplicateName')) {
            add_alert('duplicate_name');
            return (duplicate_name => 1);
        } else {

            # Not our error!
            die($@);
        }
    }

    return ();
}

# Examine the query data to validate that the submitted
# contributor is valid.  Return hash-errors, if any.
sub validate_contrib {
    my $self = shift;

    my $q = $self->query();

    my %errors = ();

    # Must have either first name or last name.
    my $first = $q->param('first');
    my $last  = $q->param('last');
    unless ((defined($first) && ($first =~ /\S+/))
        || (defined($last) && ($last =~ /\S+/)))
    {
        $errors{error_invalid_first} = 1;
        $errors{error_invalid_last}  = 1;
    }

    # Validate url
    if ($q->param('url')) {
        $errors{error_invalid_url} = 1 unless ($q->param('url') =~ /http(s?):\/\/\S+\.\S+/);
    }

    if ($q->param('email')) {
        $errors{error_invalid_email} = 1 unless ($q->param('email') =~ /\S+@\S+\.\S+/);
    }

    # Validate contrib types
    # contrib_type_ids
    my @contrib_type_ids       = ($q->param('contrib_type_ids'));
    my $all_contrib_types      = $self->get_contrib_types();
    my @valid_contrib_type_ids = ();
    foreach my $ctype (@contrib_type_ids) {
        my $is_valid = grep { $_->[0] eq $ctype } @$all_contrib_types;
        push(@valid_contrib_type_ids, $ctype) if ($is_valid);
    }
    $q->delete('contrib_type_ids');
    $q->param('contrib_type_ids', @valid_contrib_type_ids);
    $errors{error_invalid_type} = 1 unless (scalar(@valid_contrib_type_ids));

    # Add messages
    foreach my $error (keys(%errors)) {
        add_alert($error);
    }

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

    my %contrib_tmpl = (%{&CONTRIB_PROTOTYPE});

    # For each contrib prop, convert to HTML::Template compatible data
    foreach my $cf (keys(%contrib_tmpl)) {

        # Handle special case: contrib_type_ids multiple select
        if ($cf eq 'contrib_type_ids') {
            if (defined($q->param('first'))) {

                # If "first" was defined, assume that edit form has been submitted
                $contrib_tmpl{$cf} = [$q->param('contrib_type_ids')];
            } else {

                # No submission.  Load from database
                $contrib_tmpl{$cf} = [$c->contrib_type_ids()] if (ref($c));
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
        my $type            = $ct->[1];
        my $selected = (grep { $_ eq $contrib_type_id } (@{$contrib_tmpl{contrib_type_ids}}));

        push(
            @contrib_types_tmpl,
            {
                contrib_type_id => $contrib_type_id,
                type            => $type,
                selected        => $selected,
            }
        );
    }
    $contrib_tmpl{contrib_type_ids} = \@contrib_types_tmpl;

    # Display associated media image if it exists
    if (ref($c)) {
        my $image = $c->image();
        if (defined($image)) {
            $contrib_tmpl{media_id}       = $image->media_id;
            $contrib_tmpl{filename}       = $image->filename;
            $contrib_tmpl{file_size}      = sprintf("%.1fk", ($image->file_size() / 1024));
            $contrib_tmpl{thumbnail_path} = $image->thumbnail_path(relative => 1) || '';
        }
    }

    #    my $media_file = $q->param('media_file');
    #    $contrib_tmpl{media_file} = $media_file if (defined($media_file));

    # Return a reference to the tmpl-compat data
    return \%contrib_tmpl;
}

# Replace with Krang::Prefs(?)
sub get_contrib_types {
    my %pref = pkg('Pref')->get('contrib_type');
    return [map { [$_, localize($pref{$_})] } sort { $pref{$a} cmp $pref{$b} } keys %pref];
}

#
# Handle uploaded image
#
# If the contributor already has an image associated, replace the file in the existing Media object.
# Otherwise, create a new media object.
#
sub upload_image {

    my $self = shift;
    my ($contrib) = @_;

    my $q = $self->query();

    # add image to the mix, if it exists
    my $fh = $q->upload('media_file');

    return undef unless ($fh);

    my $media_file = $q->param('media_file');

    # Coerce a reasonable name from what we get
    my @filename_parts = split(/[\/\\\:]/, $media_file);
    my $filename = $filename_parts[-1];

    my $media = $contrib->image();

    unless (defined($media)) {

        # Need to save object under a category.
        # Use first category of first site - user can always change it later.
        my ($site) = pkg('Site')->find(limit => 1, order_by => 'site_id');
        my ($category) = pkg('Category')->find(site_id => $site->site_id, limit => 1);
        my %media_types    = pkg('Pref')->get('media_type');
        my @media_type_ids = keys(%media_types);

        $media = pkg('Media')->new(
            title         => 'Contributor Photo:' . $contrib->full_name,
            category_id   => $category->category_id,
            media_type_id => $media_type_ids[0]
        );
    }

    # Put the file in the Media object
    $media->upload_file(
        filehandle => $fh,
        filename   => $filename,
    );

    eval { $media->save(); };

    # if the media file has existed previously, toss this one and use the old one.
    if (ref $@ and ref $@ eq 'Krang::Media::DuplicateURL') {
        my $err = $@;

        # tell all about it
        add_alert('duplicate_media_upload', filename => $filename);

        # use the dup instead of the new object
        ($media) = pkg('Media')->find(media_id => $err->media_id);
    } elsif ($@) {
        die $@;
    }

    $q->delete('media_file');

    return $media;

}

sub autocomplete {
    my $self = shift;
    return autocomplete_values(
        table  => 'contrib',
        fields => [qw(contrib_id first middle last)],
    );
}

1;

=back

=cut

