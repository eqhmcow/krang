package Krang::CGI::Media;
use strict;
use warnings;
use Krang::ClassLoader base => 'CGI::ElementEditor';
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'Category';
use Krang::ClassLoader Conf => qw(KrangRoot);
use Krang::ClassLoader 'ElementLibrary';
use Krang::ClassLoader History => qw(add_history);
use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader Localization => qw(localize);
use Krang::ClassLoader Log          => qw(debug info critical);
use Krang::ClassLoader 'Media';
use Krang::ClassLoader 'UUID';
use Krang::ClassLoader Message => qw(add_message add_alert clear_messages);
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Widget =>
  qw(category_chooser datetime_chooser decode_datetime format_url autocomplete_values);
use Krang::ClassLoader 'IO';
use Carp qw(croak);
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use File::Spec::Functions qw(catfile catdir abs2rel);
use File::Basename qw(fileparse);
use URI::Escape qw(uri_escape);

=head1 NAME

Krang::CGI::Media - web interface to manage media

=head1 SYNOPSIS

  use Krang::ClassLoader 'CGI::Media';
  my $app = pkg('CGI::Media')->new();
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

sub setup {
    my $self = shift;

    $self->SUPER::setup();
    $self->mode_param('rm');
    $self->start_mode('find');

    $self->run_modes(
        [
            qw(
              find
              advanced_find
              add_media
              cancel_edit
              checkin_add
              checkin_edit
              checkin_selected
              save_stay_add
              checkout_and_edit
              checkout_selected
              edit
              save_edit
              save_stay_edit
              list_active
              list_retired
              delete
              delete_selected
              save_and_associate_media
              save_and_view_log
              save_and_publish
              save_and_preview
              save_and_jump
              save_and_go_up
              save_and_bulk_edit
              save_and_leave_bulk_edit
              save_and_change_bulk_edit_sep
              view
              view_log
              view_version
              revert_version
              save_and_edit_schedule
              autocomplete
              retire
              retire_selected
              unretire
              save_and_transform_image
              transform_image
              save_image_transform
              cancel_image_transform
              )
        ]
    );

    $self->tmpl_path('Media/');
}

##############################
#####  RUN-MODE METHODS  #####
##############################

=item find

The find mode allows the user to run simple and advanced searches on
live media objects, which will be listed on paging view 'Find Media'.

From this paging view the user may choose to view, edit or retire an
object, or select a set of objects to be checked out to the workspace,
published or deleted (depending on the user's permission set).

=cut

sub find {
    my $self = shift;

    $self->query->param('other_search_place' => localize('Search Retired Media'));

    my %args = (
        tmpl_file         => 'list_view.tmpl',
        include_in_search => 'live'
    );

    $self->_do_find(%args);
}

=item list_retired

The list_retired mode allows the user to run simple and advanced
searches on retired media objects, which will be listed on paging
view 'Retired Media'.

From this paging view the user may choose to view or unretire an
object, or select a set of objects to be deleted (depending on the
user's permission set).

=cut

sub list_retired {
    my $self = shift;

    $self->query->param('other_search_place' => localize('Search Live Media'));

    my %args = (
        tmpl_file         => 'list_retired.tmpl',
        include_in_search => 'retired',
    );

    $self->_do_find(%args);
}

#
# This private method dispatches find operations to _do_simple_find() or
# _do_advanced_find().
#
sub _do_find {
    my ($self, %args) = @_;

    my $q = $self->query;

    # Search mode
    my $do_advanced_search =
      defined($q->param('do_advanced_search'))
      ? $q->param('do_advanced_search')
      : $session{KRANG_PERSIST}{pkg('Media')}{do_advanced_search};

    return $do_advanced_search
      ? $self->_do_advanced_find(%args)
      : $self->_do_simple_find(%args);
}

#
# The workhorse doing simple finds.
#
sub _do_simple_find {
    my ($self, %args) = @_;

    my $q = $self->query;

    # search in Retired or in Live?
    my $include = $args{include_in_search};

    # find retired stories?
    my $retired = $include eq 'retired' ? 1 : 0;

    my $t = $self->load_tmpl($args{tmpl_file}, associate => $q);
    $t->param(do_advanced_search => 0);

    # figure out if user should see add, publish, checkin, delete
    my %user_permissions = (pkg('Group')->user_asset_permissions);
    $t->param(read_only => ($user_permissions{media} eq 'read-only'));

    # admin perms to determine appearance of Publish button and row checkbox
    my %user_admin_permissions = pkg('Group')->user_admin_permissions;
    $t->param(may_publish => $user_admin_permissions{may_publish}) unless $retired;

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

    my $search_filter =
      defined($q->param('search_filter'))
      ? $q->param('search_filter')
      : $session{KRANG_PERSIST}{pkg('Media')}{search_filter};

    my $show_thumbnails;
    if (defined($q->param('show_thumbnails'))) {
        $show_thumbnails = $q->param('show_thumbnails');
    } elsif (defined($session{KRANG_PERSIST}{pkg('Media')}{show_thumbnails})) {
        $show_thumbnails = $session{KRANG_PERSIST}{pkg('Media')}{show_thumbnails};
    } elsif (defined($q->param('show_thumbnails'))) {
        $show_thumbnails = $q->param('show_thumbnails');
    } else {
        $show_thumbnails = 1;
    }

    $session{KRANG_PERSIST}{pkg('Media')}{show_thumbnails} = $show_thumbnails;

    unless (defined($search_filter)) {

        # Define search_filter
        $search_filter = '';
    }

    # find live or retired stories?
    my %include_options = $retired ? (include_live => 0, include_retired => 1) : ();

    my $persist_vars = {
        rm => ($retired ? 'list_retired' : 'find'),
        search_filter      => $search_filter,
        show_thumbnails    => $show_thumbnails,
        asset_type         => 'media',
        $include           => 1,
        do_advanced_search => 0,
    };

    my $find_params = {
        may_see       => 1,
        simple_search => $search_filter,
        %include_options
    };

    my $pager = $self->make_pager($persist_vars, $find_params, $show_thumbnails, $retired);
    my $pager_tmpl = $self->load_tmpl(
        'list_view_pager.tmpl',
        associate         => $q,
        loop_context_vars => 1,
        global_vars       => 1,
        die_on_bad_params => 0,
    );
    $pager->fill_template($pager_tmpl);
    $pager_tmpl->param(show_thumbnails => $show_thumbnails);

    # Run pager
    $t->param(
        pager_html      => $pager_tmpl->output(),
        row_count       => $pager->row_count(),
        show_thumbnails => $show_thumbnails,
        search_filter   => $search_filter
    );

    return $t->output();
}

=item advanced_find

B<This method is deprecated, but left in here for backwards
compatibility.>

The find mode allows the user to run an "advanced search" on 
media objects, which will be listed on a paging view.

From this paging view the user may choose to edit or view
an object, or select a set of objects to be deleted.

=cut

sub advanced_find {
    my $self = shift;

    $self->query->param('do_advanced_search' => 1);

    return $self->find;
}

#
# The workhorse doing advanced finds.
#
sub _do_advanced_find {
    my ($self, %args) = @_;

    my $q = $self->query();

    # search in Retired or in Live?
    my $include = $args{include_in_search};

    # find retired stories?
    my $retired = $include eq 'retired' ? 1 : 0;

    my $t = $self->load_tmpl($args{tmpl_file}, associate => $q);
    $t->param(do_advanced_search => 1);

    # figure out if user should see add, publish, checkin, delete
    my %user_permissions = (pkg('Group')->user_asset_permissions);
    $t->param(read_only => ($user_permissions{media} eq 'read-only'));

    # admin perms to determine appearance of Publish button and row checkbox
    my %user_admin_permissions = pkg('Group')->user_admin_permissions;
    $t->param(may_publish => $user_admin_permissions{may_publish}) unless $retired;

    # if the user clicked 'clear', nuke the cached params in the session.
    if (defined($q->param('clear_search_form'))) {
        delete $session{KRANG_PERSIST}{pkg('Media')};
    }

    # Persist data for return from view in "return_params"
    my @return_param_list = qw(
      rm
      krang_pager_curr_page_num
      krang_pager_show_big_view
      krang_pager_sort_field
      krang_pager_sort_order_desc
      show_thumbnails
      search_alt_tag
      search_full_text
      search_below_category_id
      search_filename
      search_filter
      search_media_id
      search_media_type_id
      search_title
      search_tag
      search_creation_date_day
      search_creation_date_month
      search_creation_date_year
      search_creation_date_hour
      search_creation_date_minute
      search_creation_date_ampm
      do_advanced_search
    );

    $t->param(return_params => $self->make_return_params(@return_param_list));

    # find live or retired stories?
    my %include_options = $retired ? (include_live => 0, include_retired => 1) : ();

    my $find_params = \%include_options;

    my $persist_vars = {
        rm => ($retired ? 'list_retired' : 'find'),
        asset_type         => 'media',
        do_advanced_search => 1,
        $include           => 1,
    };

    my $show_thumbnails;
    if (defined($q->param('search_filename'))) {
        $show_thumbnails = $q->param('show_thumbnails');
    } elsif (defined($q->param('show_thumbnails'))) {
        $show_thumbnails = $q->param('show_thumbnails');
    } elsif (defined($session{KRANG_PERSIST}{pkg('Media')}{show_thumbnails})) {
        $show_thumbnails = $session{KRANG_PERSIST}{pkg('Media')}{show_thumbnails};
    } else {
        $show_thumbnails = 1;
    }

    $session{KRANG_PERSIST}{pkg('Media')}{show_thumbnails} = $show_thumbnails;
    $persist_vars->{show_thumbnails} = $show_thumbnails;

    # Build find params
    my $search_below_category_id =
      defined($q->param('search_below_category_id'))
      ? $q->param('search_below_category_id')
      : $session{KRANG_PERSIST}{pkg('Media')}{cat_chooser_id_search_form_search_below_category_id};
    if (defined($search_below_category_id)) {
        $persist_vars->{search_below_category_id} = $search_below_category_id;
        $find_params->{below_category_id}         = $search_below_category_id;
    }

    my $search_creation_date_from = decode_datetime(
        query => $q,
        name  => 'search_creation_date_from',
    );
    my $search_creation_date_to = decode_datetime(
        no_time_is_end => 1,
        query          => $q,
        name           => 'search_creation_date_to',
    );

    if ($search_creation_date_from and $search_creation_date_to) {
        $find_params->{creation_date} = [$search_creation_date_from, $search_creation_date_to];
    } elsif ($search_creation_date_from) {
        $find_params->{creation_date} = [$search_creation_date_from, undef];
    } elsif ($search_creation_date_to) {
        $find_params->{creation_date} = [undef, $search_creation_date_to];
    }

    # persist dates if set, delete them if not
    for (qw/day month year hour minute ampm/) {
        my $varname = "search_creation_date_from_$_";
        if ($search_creation_date_from) {
            $persist_vars->{$varname} = $q->param($varname);
        } else {
            $q->delete($varname);
        }

        $varname = "search_creation_date_to_$_";
        if ($search_creation_date_to) {
            $persist_vars->{$varname} = $q->param($varname);
        } else {
            $q->delete($varname);
        }
    }

    # search_filename
    my $search_filename =
      defined($q->param('search_filename'))
      ? $q->param('search_filename')
      : $session{KRANG_PERSIST}{pkg('Media')}{search_filename};

    if (defined($search_filename)) {
        $find_params->{filename_like}    = "\%$search_filename\%";
        $persist_vars->{search_filename} = $search_filename;
        $t->param(search_filename => $search_filename);
    }

    # search_alt_tag
    my $search_alt_tag =
      defined($q->param('search_alt_tag'))
      ? $q->param('search_alt_tag')
      : $session{KRANG_PERSIST}{pkg('Media')}{search_alt_tag};

    if ($search_alt_tag) {
        $search_alt_tag =~ s/\W+/\%/g;
        $find_params->{alt_tag_like}    = "\%$search_alt_tag\%";
        $persist_vars->{search_alt_tag} = $search_alt_tag;
        $t->param(search_alt_tag => $search_alt_tag);
    }

    # search_full_text
    my $search_full_text =
      defined($q->param('search_full_text'))
      ? $q->param('search_full_text')
      : $session{KRANG_PERSIST}{pkg('Media')}{search_full_text};

    if ($search_full_text) {
        $find_params->{full_text} = $search_full_text;
        $persist_vars->{search_full_text} = $search_full_text;
        $t->param(search_full_text => $search_full_text);
    }

    # search_title
    my $search_title =
      defined($q->param('search_title'))
      ? $q->param('search_title')
      : $session{KRANG_PERSIST}{pkg('Media')}{search_title};

    if (defined($search_title)) {
        $search_title =~ s/\W+/\%/g;
        $find_params->{title_like}    = "\%$search_title\%";
        $persist_vars->{search_title} = $search_title;
        $t->param(search_title => $search_title);
    }

    # search_tag
    my $search_tag =
      defined($q->param('search_tag'))
      ? $q->param('search_tag')
      : $session{KRANG_PERSIST}{pkg('Media')}{search_tag};

    if (defined($search_tag)) {
        $find_params->{tag}         = $search_tag;
        $persist_vars->{search_tag} = $search_tag;
    }
    my @tags    = pkg('Media')->known_tags();
    my $chooser = $q->popup_menu(
        -name    => 'search_tag',
        -default => ($persist_vars->{search_tag} || ''),
        -values  => ['', @tags],
    );
    $t->param(search_tag_chooser => $chooser);

    # search_media_id
    my $search_media_id =
      defined($q->param('search_media_id'))
      ? $q->param('search_media_id')
      : $session{KRANG_PERSIST}{pkg('Media')}{search_media_id};

    if (defined($search_media_id)) {
        $find_params->{media_id}         = $search_media_id;
        $persist_vars->{search_media_id} = $search_media_id;
        $t->param(search_media_id => $search_media_id);
    }

    # search_media_type_id
    my $search_media_type_id =
      defined($q->param('search_media_type_id'))
      ? $q->param('search_media_type_id')
      : $session{KRANG_PERSIST}{pkg('Media')}{search_media_type_id};

    if (defined($search_media_type_id)) {
        $find_params->{media_type_id}         = $search_media_type_id;
        $persist_vars->{search_media_type_id} = $search_media_type_id;
        #        $t->param(search_media_type_id => $search_media_type_id);
    }

    # search_no_attributes
    my $search_no_attributes =
      ($q->param('rm') eq 'advanced_find')
      ? $q->param('search_no_attributes')
      : $session{KRANG_PERSIST}{pkg('Media')}{search_no_attributes};

    $find_params->{no_attributes}         = $search_no_attributes;
    $persist_vars->{search_no_attributes} = $search_no_attributes;
    $t->param(search_no_attributes => $search_no_attributes);

    # Run pager
    my $pager = $self->make_pager($persist_vars, $find_params, $show_thumbnails, $retired);
    my $pager_tmpl = $self->load_tmpl(
        'list_view_pager.tmpl',
        associate         => $q,
        loop_context_vars => 1,
        global_vars       => 1,
        die_on_bad_params => 0,
    );
    $pager->fill_template($pager_tmpl);
    $pager_tmpl->param(show_thumbnails => $show_thumbnails);

    $t->param(
        pager_html       => $pager_tmpl->output(),
        row_count        => $pager->row_count(),
        show_thumbnails  => $show_thumbnails,
        category_chooser => scalar(
            category_chooser(
                query      => $q,
                name       => 'search_below_category_id',
                formname   => 'search_form',
                persistkey => pkg('Media'),
            )
        ),
        date_from_chooser => datetime_chooser(
            query    => $q,
            name     => 'search_creation_date_from',
            nochoice => 1,
        ),
        date_to_chooser => datetime_chooser(
            query    => $q,
            name     => 'search_creation_date_to',
            nochoice => 1,
        ),
        date_to_chooser => datetime_chooser(
            query    => $q,
            name     => 'search_creation_date_to',
            nochoice => 1,
        ),
        type_chooser => $self->_media_types_popup_menu(search => 1,),
    );

    return $t->output();
}

=item list_active

List all active media.  Provide links to view each media object.  If the
user has 'checkin all' admin abilities then checkboxes are provided to
allow the media to be checked-in.

=cut

sub list_active {
    my $self = shift;
    my $q    = $self->query();

    # Set up persist_vars for pager
    my %persist_vars = (rm => 'list_active');

    # Set up find_params for pager
    my %find_params = (checked_out => 1, may_see => 1);

    # can checkin all?
    my %admin_perms     = pkg('Group')->user_admin_permissions();
    my $may_checkin_all = $admin_perms{may_checkin_all};

    my $pager = pkg('HTMLPager')->new(
        cgi_query    => $q,
        persist_vars => \%persist_vars,
        use_module   => pkg('Media'),
        find_params  => \%find_params,
        columns      => [
            (
                qw(
                  media_id
                  thumbnail
                  title
                  url
                  user
                  commands_column
                  )
            ),
            ($may_checkin_all ? ('checkbox_column') : ())
        ],
        column_labels => {
            media_id        => 'ID',
            thumbnail       => 'Thumbnail',
            title           => 'Title',
            url             => 'URL',
            user            => 'User',
            commands_column => '',
        },
        columns_sortable => [qw( media_id title url )],
        row_handler      => sub { $self->list_active_row_handler(@_); },
        id_handler       => sub { return $_[0]->media_id },
    );

    my $pager_tmpl = $self->load_tmpl(
        'list_active_pager.tmpl',
        die_on_bad_params => 0,
        loop_context_vars => 1,
        global_vars       => 1,
        associate         => $q,
    );
    $pager->fill_template($pager_tmpl);

    # Set up output
    my $template = $self->load_tmpl('list_active.tmpl', associate => $q);
    $template->param(
        pager_html      => $pager_tmpl->output,
        row_count       => $pager->row_count,
        may_checkin_all => $may_checkin_all,
    );
    return $template->output;
}

=item add_media

The "add_media" run-mode displays the form through which
new Media objects may be added to Krang.

=cut

sub add_media {
    my $self = shift;
    my %args = (@_);

    # Create new temporary Media object to work on
    my $m = pkg('Media')->new();
    $self->set_edit_object($m);

    # Call and return the real add function
    return $self->_add(%args);
}

=item checkin_add 

Save the new media object, then check it in. Redirect to 
My Workspace afterwards, even tho the media object will not be there.

=cut

sub checkin_add {
    my $self = shift;
    my $q    = $self->query();
    my $m    = $self->get_edit_object;

    # Update object in session
    $self->update_media($m) || return $self->redirect_to_workspace;

    # Validate input.  Return errors, if any.
    my %errors = $self->validate_media($m);
    return $self->_add(%errors) if (%errors);

    # Save object to database
    my %save_errors = ($self->do_save_media($m));
    return $self->_add(%save_errors) if (%save_errors);

    # check in
    $m->checkin();

    # Notify user
    add_message("new_media_saved");

    # Clear media object from session
    $self->clear_edit_object();

    # Redirect to workspace.pl
    $self->redirect_to_workspace;

}

=item save_stay_add

Saves the new object and redirects to edit screen
(Triggered by 'create' button.)

=cut

sub save_stay_add {
    my $self = shift;
    my $q    = $self->query();
    my $m    = $self->get_edit_object;

    # Update object in session
    $self->update_media($m) || return $self->redirect_to_workspace;

    # Validate input.  Return errors, if any.
    my %errors = $self->validate_media($m);
    return $self->_add(%errors) if (%errors);

    # Save object to database
    my %save_errors = ($self->do_save_media($m));
    return $self->_add(%save_errors) if (%save_errors);

    # Publish to preview
    $m->preview();

    # Checkout to Workspace
    eval { $m->checkout() };
    if (my $e = $@) {
        if (ref $e && $e->isa('Krang::Media::CheckedOut')) {
            add_alert('media_modified_elsewhere', id => $m->media_id);
            return $self->redirect_to_workspace;
        } elsif (ref $e && $e->isa('Krang::Media::NoEditAccess')) {
            add_alert('media_permissions_changed_edit', id => $m->media_id);
            return $self->redirect_to_workspace;
        } else {
            die $e;    # rethrow
        }
    }

    # Notify user
    add_message("new_media_saved");

    # Cancel should now redirect to Workspace since we created a new version
    $self->_cancel_edit_goes_to('workspace.pl', $ENV{REMOTE_USER});

    # Redirect to edit mode
    my $url = $q->url(-relative => 1);
    $url .= "?rm=edit&media_id=" . $m->media_id();
    $self->header_props(-uri => $url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}

=item checkout_and_edit

Checks out the media object identified by media_id and sends the user
to edit.

=cut

sub checkout_and_edit {
    my $self = shift;
    my $q    = $self->query();

    my $media_id = $q->param('media_id');
    croak("Missing required media_id parameter.") unless $media_id;

    my ($m) = pkg('Media')->find(media_id => $media_id);
    croak("Unable to load media_id '$media_id'") unless $m;

    $self->_cancel_edit_goes_to('media.pl?rm=find', $m->checked_out_by);

    eval { $m->checkout };
    if (my $e = $@) {
        if (ref $e && $e->isa('Krang::Media::CheckedOut')) {
            add_alert('checked_out', id => $m->media_id, file => $m->filename);
            return $self->redirect_to_workspace;
        } elsif (ref $e && $e->isa('Krang::Media::NoEditAccess')) {
            add_alert('media_permissions_changed', id => $m->media_id);
            return $self->redirect_to_workspace;
        } else {
            die $e;    # rethrow
        }
    }

    return $self->edit;
}

=item edit

The "edit" mode displays the form through which
users may edit existing Media objects.

=cut

sub edit {
    my ($self, %args) = @_;
    my $q        = $self->query();
    my $media_id = $self->edit_object_id;
    my $m        = $self->get_edit_object();

    # we expect a media object with an ID, if we don't have it go to add mode
    if (!$m->media_id) {
        # Redirect to add mode
        return $self->_add(%args);
    }

    # Do we need to reload the media object?
    if ($q->param('force_reload')) {
        ($m) = pkg('Media')->find(media_id => $media_id);
        die("Can't find media object with media_id '$media_id'") unless $m;
        $self->set_edit_object($m, keep_edit_uuid => 1);
    }

    my $t = $self->load_tmpl(
        'edit_media.tmpl',
        associate         => $q,
        loop_context_vars => 1,
        die_on_bad_params => 0
    );
    # so the return param for rm is 'edit' even after a 'save_stay_edit', etc.
    $self->query->param(rm => 'edit');
    my $media_tmpl_data = $self->make_media_tmpl_data($m);
    $t->param($media_tmpl_data);

    # run the element editor edit
    $self->element_edit(template => $t, element => $m->element);

    # permissions
    my %admin_perms = pkg('Group')->user_admin_permissions();
    $t->param(may_publish => $admin_perms{may_publish});
    $t->param(may_edit_schedule => $admin_perms{admin_scheduler} || $admin_perms{admin_jobs});

    # Propagate messages, if we have any
    $t->param(%args) if (%args);

    # keep track of whether we're at the top level of element or not
    my $path = $self->query->param('path');
    $t->param(is_root => 1) unless ($path && $path ne '/');

    # this affects display in ElementEditor.tmpl
    $t->param(elements_belong_to_media_object => 1);

    $t->param(cancel_changes_owner     => $self->_cancel_edit_changes_owner);
    $t->param(cancel_goes_to_workspace => $self->_cancel_edit_goes_to_workspace);

    return $t->output();
}

=item save_edit

Validate and save the form content to the media object.
Redirect the user to their Workspace.

=cut

sub save_edit {
    my $self = shift;

    # Validate & save object in session
    my $output = $self->_save();
    return $output if $output;

    # Save object to database
    my $m           = $self->get_edit_object;
    my %save_errors = ($self->do_save_media($m));
    return $self->edit(%save_errors) if (%save_errors);

    # Publish to preview
    $m->preview();

    # Checkout to Workspace
    eval { $m->checkout() };
    if (my $e = $@) {
        if (ref $e && $e->isa('Krang::Media::CheckedOut')) {
            add_alert('media_modified_elsewhere', id => $m->media_id);
            return $self->redirect_to_workspace;
        } elsif (ref $e && $e->isa('Krang::Media::NoEditAccess')) {
            add_alert('media_permissions_changed_edit', id => $m->media_id);
            return $self->redirect_to_workspace;
        } else {
            die $e;    # rethrow
        }
    }

    # Notify user
    add_message("media_saved");

    # Clear media object from session
    $self->clear_edit_object();

    # Redirect to workspace.pl
    $self->redirect_to_workspace;
}

=item checkin_edit

Validate and save the form content to the media object.
Checkin media object.
Redirect the user to their Workspace.

=cut

sub checkin_edit {
    my $self = shift;

    # Validate and save object in session
    my $output = $self->_save();
    return $output if $output;

    # Save object to database
    my $m           = $self->get_edit_object();
    my %save_errors = ($self->do_save_media($m));
    return $self->edit(%save_errors) if (%save_errors);

    # Checkin
    $m->checkin();

    # Notify user
    add_message("media_saved");

    # Clear media object from session
    $self->clear_edit_object();

    # Redirect to workspace.pl
    $self->redirect_to_workspace;
}

=item save_stay_edit

Validate and save the form content to the media object.
Return the user to the edit screen.


=cut

sub save_stay_edit {
    my $self = shift;

    # Validate and save object in session
    my $output = $self->_save();
    return $output if $output;

    # Save object to database
    my $m           = $self->get_edit_object();
    my %save_errors = ($self->do_save_media($m));
    return $self->edit(%save_errors) if (%save_errors);

    # Publish to preview
    $m->preview();

    # Checkout to Workspace
    eval { $m->checkout };
    if (my $e = $@) {
        if (ref $e && $e->isa('Krang::Media::CheckedOut')) {
            add_alert('media_modified_elsewhere', id => $m->media_id);
            return $self->redirect_to_workspace;
        } elsif (ref $e && $e->isa('Krang::Media::NoEditAccess')) {
            add_alert('media_permissions_changed_edit', id => $m->media_id);
            return $self->redirect_to_workspace;
        } else {
            die $e;    # rethrow
        }
    }

    # Notify user
    add_message("media_saved");

    # if Story wasn't ours to begin with, Cancel should now
    # redirect to our Workspace since we created a new version
    $self->_cancel_edit_goes_to('workspace.pl', $ENV{REMOTE_USER})
      if $self->_cancel_edit_changes_owner;

    # Redirect to edit mode
    return $self->edit;
}

=item delete

Trashes the media object specified by CGI form 
parameter 'media_id'.  Redirect user to Workspace.

=cut

sub delete {
    my $self = shift;
    my $m    = $self->get_edit_object;

    # Transfer to trash
    $m->trash();
    $self->clear_edit_object();

    add_message('message_media_deleted');

    # Redirect to workspace.pl
    $self->redirect_to_workspace;
}

=item delete_selected

Trashes the media objects which have been selected (checked) from the
find mode list view.  This mode expects selected media objects to be
specified in the CGI param C<krang_pager_rows_checked>.

=cut

sub delete_selected {
    my $self = shift;

    my $q                 = $self->query();
    my @media_delete_list = ($q->param('krang_pager_rows_checked'));
    $q->delete('krang_pager_rows_checked');

    # No selected media?  Just return to list view without any message
    return $self->find() unless (@media_delete_list);

    foreach my $mid (@media_delete_list) {
        pkg('Media')->trash(media_id => $mid);
    }

    add_message('message_selected_deleted');

    return $q->param('retired') ? $self->list_retired : $self->find;
}

=item retire_selected

Retires the media objects which have been selected (checked) from the
find mode list view.  This mode expects selected media objects to be
specified in the CGI param C<krang_pager_rows_checked>.

=cut

sub retire_selected {
    my $self = shift;

    my $q                 = $self->query();
    my @media_retire_list = ($q->param('krang_pager_rows_checked'));
    $q->delete('krang_pager_rows_checked');

    # No selected media?  Just return to list view without any message
    return $self->find() unless (@media_retire_list);

    foreach my $mid (@media_retire_list) {
        pkg('Media')->retire(media_id => $mid);
    }

    add_message('message_selected_retired');
    return $self->find;
}

=item save_and_edit_schedule

This mode saves the current data to the session and passes control to
edit schedule for media.

=cut

sub save_and_edit_schedule {
    my $self      = shift;
    my $edit_uuid = $self->edit_uuid;

    # Update media object in session
    my $output = $self->_save();
    return $output if $output;

    # Redirect to scheduler
    my $url = "schedule.pl?rm=edit&object_type=media&edit_uuid=$edit_uuid";
    $self->header_props(-uri => $url);
    $self->header_type('redirect');
    return "Redirect: <a href=\"$url\">$url</a>";
}

=item save_and_associate_media

The purpose of this mode is to hand the user off to the
associate contribs screen.  This mode writes changes back 
to the media object without calling save().  When done,
it performs an HTTP redirect to:

  contributor.pl?rm=associate_media

=cut

sub save_and_associate_media {
    my $self      = shift;
    my $edit_uuid = $self->edit_uuid;

    # Update media object in session
    my $output = $self->_save();
    return $output if $output;

    # Redirect to associate-media screen
    my $url = "contributor.pl?rm=associate_media&edit_uuid=$edit_uuid";
    $self->header_props(-uri => $url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}

=item save_and_publish

This mode writes changes back to the media object, calls save() and
then redirects to publisher.pl to publish the media object.

=cut

sub save_and_publish {
    my $self = shift;

    # Validate and save object in session
    my $output = $self->_save();
    return $output if $output;

    # Save object to database
    my $m           = $self->get_edit_object();
    my %save_errors = ($self->do_save_media($m));
    return $self->edit(%save_errors) if (%save_errors);

    # publish should also send to preview
    $m->preview;

    # Clear media object from session
    $self->clear_edit_object();

    # Redirect to publish screen
    my $url = 'publisher.pl?rm=publish_media&media_id=' . $m->media_id;
    $self->header_props(-uri => $url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}

=item

This mode writes changes back to the media object, calls save() and
then redirects to publisher.pl to preview the media object.

=cut

sub save_and_preview {
    my $self      = shift;
    my $media_id  = $self->edit_object_id;
    my $edit_uuid = $self->edit_uuid;

    # Validate and save object in session
    my $output = $self->_save();
    return $output if $output;

    # Redirect to preview screen
    my $url = "publisher.pl?rm=preview_media&no_view=1&media_id=$media_id&edit_uuid=$edit_uuid";
    $self->header_props(-uri => $url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}

=item save_and_view_log

The purpose of this mode is to hand the user off to the log viewing
screen.  This mode writes changes back to the media object without
calling save().  When done, it performs an HTTP redirect to
history.pl.

=cut

sub save_and_view_log {
    my $self      = shift;
    my $id        = $self->edit_object_id;
    my $edit_uuid = $self->edit_uuid;

    # Update media in session
    my $output = $self->_save();
    return $output if $output;

    # Redirect to history screen
    my $url =
        "history.pl?history_return_script=media.pl"
      . "&history_return_params=rm&history_return_params=edit"
      . "&history_return_params=media_id&history_return_params=$id"
      . "&history_return_params=edit_uuid&history_return_params=$edit_uuid"
      . "&id=$id&class=Media&id_meth=media_id";
    $self->header_props(-uri => $url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}

=item view_log

The purpose of this mode is to hand the user off to the log viewing
screen but preserving where we came from.

=cut

sub view_log {
    my $self     = shift;
    my $q        = $self->query();
    my %return   = $q->param('return_params');
    my $media_id = $self->edit_object_id;

    # default return vars
    $return{rm} ||= 'view';
    $return{edit_uuid} ||= $self->edit_uuid;

    # Redirect to history screen
    my $url = "history.pl?history_return_script=media.pl&" . join(
        '&',
        map {
                'history_return_params='
              . uri_escape($_)
              . '&history_return_params='
              . uri_escape($return{$_})
          } (keys %return)
    ) . "&id=$media_id&class=Media&id_meth=media_id";
    $self->header_props(-uri => $url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}

=item view

Display the specified media object in a view form.

=cut

sub view {
    my $self    = shift;
    my $version = shift;

    my $q = $self->query();
    my $t = $self->load_tmpl('view_media.tmpl', loop_context_vars => 1);

    $version ||= $q->param('version');

    # get media_id from params or from the media in the session
    my $media_id = $self->edit_object_id;
    die("No media_id specified") unless ($media_id);

    # Load media object into session, or die trying
    my %find_params = ();
    $find_params{media_id} = $media_id;

    # Handle viewing old version
    if ($version) {
        $find_params{version} = $version;
        $t->param(is_old_version => 1);
    }

    my ($m) = pkg('Media')->find(%find_params);
    die("Can't find media object with media_id '$media_id'") unless (ref($m));

    my $media_view_tmpl_data = $self->make_media_view_tmpl_data($m);
    $t->param($media_view_tmpl_data);

    # run the element editor view
    $self->element_view(template => $t, element => $m->element);

    # keep track of whether we're at root of element
    my $path = $self->query->param('path');
    $t->param(is_root => 1) unless ($path && $path ne '/');

    return $t->output();
}

=item view_version

Display the specified version of the media object in a view form.

=cut

sub view_version {
    my $self = shift;

    my $q                = $self->query();
    my $selected_version = $q->param('selected_version');

    die("Invalid selected version '$selected_version'")
      unless ($selected_version and $selected_version =~ /^\d+$/);

    # Update media object in session
    my $output = $self->_save();
    return $output if $output;

    # Return view mode with version
    return $self->view($selected_version);
}

=item revert_version

Send the user to an edit screen, replacing the object with the 
specified version of itself.

=cut

sub revert_version {
    my $self             = shift;
    my $q                = $self->query();
    my $selected_version = $q->param('selected_version');
    my $m                = $self->get_edit_object();

    die("Invalid selected version '$selected_version'")
      unless ($selected_version and $selected_version =~ /^\d+$/);

    # clean query
    $q->delete_all();
    $q->param(reverted_to_version => $selected_version);

    # Perform revert & display result
    my $pre_revert_version = $m->version;
    my $result             = $m->revert($selected_version);
    if ($result->isa('Krang::Media')) {
        add_message(
            "message_revert_version",
            new_version => $m->version,
            old_version => $selected_version
        );
    } else {
        my %save_errors = ($self->do_save_media($m));
        add_alert("message_revert_version_no_save", old_version => $selected_version);
        return $self->edit(%save_errors);
    }

    # Redirect to edit mode
    return $self->edit();
}

=item checkin_selected

Checkin all the media which were checked on the list_active screen.

=cut

sub checkin_selected {
    my $self = shift;

    my $q                  = $self->query();
    my @media_checkin_list = ($q->param('krang_pager_rows_checked'));
    $q->delete('krang_pager_rows_checked');

    foreach my $media_id (@media_checkin_list) {
        my ($m) = pkg('Media')->find(media_id => $media_id);
        $m->checkin();
    }

    if (scalar(@media_checkin_list)) {
        add_message('selected_media_checkin');
    }

    return $self->list_active;
}

=item checkout_selected

Checkout all the media which were checked on the list_active screen.

=cut

sub checkout_selected {
    my $self = shift;

    my $q                   = $self->query();
    my @media_checkout_list = ($q->param('krang_pager_rows_checked'));
    $q->delete('krang_pager_rows_checked');

    foreach my $media_id (@media_checkout_list) {
        my ($m) = pkg('Media')->find(media_id => $media_id);
        eval { $m->checkout() };
        if (my $e = $@) {
            if (ref $e && $e->isa('Krang::Media::CheckedOut')) {
                add_alert('checked_out', id => $m->media_id, file => $m->filename);
            } elsif (ref $e && $e->isa('Krang::Media::NoEditAccess')) {
                add_alert('media_permissions_changed', id => $m->media_id);
            } else {
                die $e;    # rethrow
            }
        }

    }

    if (scalar(@media_checkout_list)) {
        add_message('selected_media_checkout');
    }

    # Redirect to workspace.pl
    $self->redirect_to_workspace;

}

# ELEMENT-EDITOR-SPECIFIC RUNMODES

=item save_and_jump

This mode saves the current data to the session and jumps to editing
an element within the media.

=cut

sub save_and_jump {
    my $self   = shift;
    my $output = $self->_save();
    return $output if $output;

    my $query = $self->query;
    my $jump_to = $query->param('jump_to') || croak("Missing jump_to on save_and_jump!");

    $query->param(path      => $jump_to);
    $query->param(bulk_edit => 0);
    return $self->edit();
}

=item save_and_bulk_edit

This mode saves the current element data to the session and goes to
the bulk edit mode.

=cut

sub save_and_bulk_edit {
    my $self   = shift;
    my $output = $self->_save();
    return $output if $output;

    $self->query->param(bulk_edit => 1);
    return $self->edit();
}

=item save_and_change_bulk_edit_sep

Saves and changes the bulk edit separator, returning to edit.

=cut

sub save_and_change_bulk_edit_sep {
    my $self   = shift;
    my $output = $self->_save();
    return $output if $output;

    my $query = $self->query;
    $query->param(bulk_edit_sep => $query->param('new_bulk_edit_sep'));
    $query->delete('new_bulk_edit_sep');
    return $self->edit();
}

=item save_and_leave_bulk_edit

This mode saves the current element data to the session and goes to
the edit mode.

=cut

sub save_and_leave_bulk_edit {
    my $self   = shift;
    my $output = $self->_save();
    return $output if $output;

    $self->query->param(bulk_edit => 0);
    return $self->edit();
}

=item save_and_go_up

This mode saves the current element data to the session and jumps to
edit the parent of this element.

=cut

sub save_and_go_up {
    my $self   = shift;
    my $output = $self->_save();
    return $output if $output;

    my $query = $self->query;
    my $path  = $query->param('path');
    $path =~ s!/[^/]+$!!;

    $query->param(path => $path);
    return $self->edit();
}

#############################
#####  PRIVATE METHODS  #####
#############################

# underlying save routine.  returns false on success or HTML to show
# to the user on failure.
sub _save {
    my ($self, %args) = @_;
    my $query = $self->query;

    # run element editor save and return to edit on errors
    my $m = $self->get_edit_object();
    $self->element_save(element => $m->element) || return $self->edit;

    # if we're saving in the root then save the media data
    if (($query->param('path') || '/') eq '/') {
        $self->update_media($m) || return $self->redirect_to_workspace;
        my %errors = $self->validate_media($m);
        return $self->edit(%errors) if %errors;
    }

    return '';
}

# Validate media object to check validity.  Return errors as hash and add_alert()s.
# Must pass in $media object
sub validate_media {
    my $self  = shift;
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

    # Validate: filename to upload or text-file to create...
    if (!$media->filename) {
        my %types = pkg('Pref')->get('media_type');
        my $type  = $types{$media_type_id};
        unless ('html include javascript stylesheet text' =~ /\b$type\b/i) {

            # binary types require upload
            push(@errors, 'error_media_file');
        } elsif (!@errors) {

            # text types allow auto-creation from title
            $media->filename($media->title);
            open(my $filehandle);
            $media->upload_file(
                filehandle => $filehandle,
                filename   => $media->filename,
            );
            add_message('empty_file_created', filename => $media->filename);

            # Remember that a file was created (affects dupe-URL error)
            $self->query->param('created_empty_file' => 1);
        }
    }

    # Add messages, return hash for errors
    my %hash_errors = ();
    foreach my $error (@errors) {
        add_alert($error);
        $hash_errors{$error} = 1;
    }

    return %hash_errors;
}

# Pager row handler for media list active run-mode
sub list_active_row_handler {
    my $self = shift;
    my ($row, $media, $pager) = @_;
    my $q = $self->query;

    # Columns:
    #

    # media_id
    my $media_id = $media->media_id();
    $row->{media_id} = $media_id;

    # thumbnail path
    my $thumbnail_path = $media->thumbnail_path(relative => 1);
    if ($thumbnail_path) {
        $row->{thumbnail} =
          qq{<a href="" name="media_$media_id" class="media-preview-link"><img src="$thumbnail_path" border="0" class="thumbnail"></a>};
    } else {
        $row->{thumbnail} = "&nbsp;";
    }

    # format url to fit on the screen and to link to preview
    $row->{url} = format_url(
        url   => $media->url(),
        class => 'media-preview-link',
        name  => "media_$media_id",
    );

    # title
    $row->{title} = $q->escapeHTML($media->title);

    # commands column
    my %txt = map { $_ => localize($_) } (qw(View Detail Log));
    $row->{commands_column} = qq|
        <ul>
          <li class="menu">
            <input value="$txt{View} &#9660;" onclick="return false;" class="button" type="button">
            <ul>
              <li><a href="javascript:view_media($media_id)">$txt{Detail}</a></li>
              <li><a href="javascript:view_log($media_id)">$txt{Log}</a></li>
            </ul>
          </li>
        </ul>
    |;

    # user
    my ($user) = pkg('User')->find(user_id => $media->checked_out_by);
    $row->{user} = $q->escapeHTML($user->first_name . " " . $user->last_name);
}

# Return an add form.  This method expects a media object in the session.
sub _add {
    my ($self, %args) = @_;
    my $q = $self->query();
    my $t = $self->load_tmpl('edit_media.tmpl', associate => $q, loop_context_vars => 1);
    my $m = $self->get_edit_object();

    $t->param(add_mode => 1);

    my $media_tmpl_data = $self->make_media_tmpl_data($m);
    $t->param($media_tmpl_data);

    # permissions
    my %admin_perms = pkg('Group')->user_admin_permissions();
    $t->param(may_publish => $admin_perms{may_publish});

    # Propagate messages, if we have any
    $t->param(%args) if (%args);

    return $t->output();
}

# Update the provided Media object with data from the CGI form.
# Does NOT call save
sub update_media {
    my $self = shift;
    my $m    = shift;

    # Make sure object hasn't been modified elsewhere
    if (my $id = $m->media_id) {
        if (my ($media_in_db) = pkg('Media')->find(media_id => $id)) {
            if (  !$media_in_db->checked_out
                || $media_in_db->checked_out_by ne $ENV{REMOTE_USER}
                || $media_in_db->version > $m->version)
            {
                add_alert('media_modified_elsewhere', id => $id);
                $self->clear_edit_object();
                return 0;
            }
        } else {
            add_alert('media_deleted_elsewhere', id => $id);
            $self->clear_edit_object();
            return 0;
        }
    }

    # We're safe to continue...
    my $q        = $self->query();
    my @m_fields = qw(
      title
      media_type_id
      category_id
      media_file
      text_content
      caption
      copyright
      alt_tag
      notes
    );

    # unset the 'published' flag if the category has changed
    if (!$m->category_id
        || ($q->param('category_id') && $m->category_id != $q->param('category_id')))
    {
        $m->published(0);
    }

    foreach my $mf (@m_fields) {

        # Handle file upload
        if ($mf eq 'media_file') {
            my $filehandle = $q->upload('media_file');
            next unless ($filehandle);

            my $media_file = $q->param('media_file');

            # Coerce a reasonable name from what we get
            my @filename_parts = split(/[\/\\\:]/, $media_file);
            $m->filename($filename_parts[-1]);

            # Put the file in the Media object
            $m->upload_file(
                filehandle => $filehandle,
                filename   => $m->filename,
            );

            next;
        }

        # Handle direct text-file editing
        if ($mf eq 'text_content') {
            my $text = $q->param('text_content') || next;

            # Upload takes precedence over inline edit
            next if $q->param('media_file');

            # Put the file in the Media object
            $m->store_temp_file(
                content  => $text,
                filename => $m->filename,
            );

            next;
        }

        # Default: Grab scalar value from CGI form
        my $val = $q->param($mf);
        $m->$mf($val);

        # Clear param and continue
        #$q->delete($mf);
    }

    # save the tags
    my $tags = $q->param('tags') || '';
    $m->tags([split(/\s*,\s/, $tags)]);

    # Success
    return 1;
}

# Given a media object, $m, return a hashref with all the data needed
# for the edit template.
sub make_media_tmpl_data {
    my ($self, $m) = @_;
    my $q         = $self->query();
    my %tmpl_data = ();

    # Set up details only found on edit (not add) view
    if ($tmpl_data{media_id} = $m->media_id()) {
        my $thumbnail_path = $m->thumbnail_path(relative => 1) || '';
        $tmpl_data{thumbnail_path}    = $thumbnail_path;
        $tmpl_data{published_version} = $m->published_version();
        $tmpl_data{version}           = $m->version();

        if (my $url = $m->url) {
            $tmpl_data{url} = format_url(
                url    => $url,
                class  => 'media-preview-link',
                name   => 'media_' . $self->edit_uuid,
                length => 50
            );
        }

        # Display creation_date
        my $creation_date = $m->creation_date();
        $tmpl_data{creation_date} = $creation_date->strftime(localize('%m/%d/%Y %I:%M %p'));

        # Set up versions drop-down
        my $curr_version          = $tmpl_data{version};
        my $media_version_chooser = $q->popup_menu(
            -name     => 'selected_version',
            -values   => $m->all_versions,
            -default  => ($q->param('reverted_to_version') || $curr_version),
            -override => 1,
            -class    => 'usual',
        );
        $tmpl_data{media_version_chooser} = $media_version_chooser;
    }

    my $extension = $m->file_path && $m->file_path =~ /\.([^\.]+)$/ ? $1 : '';
    if ($m->is_text) {
        $tmpl_data{is_text} = 1;

        # populate template with the file's contents
        pkg('IO')->open(my $FILE, '<', $m->file_path)
          or croak "unable to open media file " . $m->file_path . " - $!";
        my $text_content = join '', <$FILE>;
        close $FILE;
        $tmpl_data{text_content} = $text_content;

        # populate template with the syntax-highlighting "language"
        my $text_type     = 'html';    # the default
        my %extension_map = (
            js  => 'javascript',
            css => 'css',
            php => 'php',
            pl  => 'perl',
        );
        $text_type = $extension_map{$extension} if $extension_map{$extension};
        debug("CodePress text type: $text_type");
        $tmpl_data{text_type}     = $text_type;
        $tmpl_data{use_codepress} = pkg('MyPref')->get('syntax_highlighting');

    } elsif ($m->is_image) {
        $tmpl_data{is_image} = 1;

        # can we transform it with Imager? Try and if it blows up we can't
        eval { Imager->new->open(file => $m->file_path) or die };
        $tmpl_data{can_transform_image} = $@ ? 0 : 1;
    }

    # persist media_type_id in session for next time someone adds media..
    $session{KRANG_PERSIST}{pkg('Media')}{media_type_id} = $m->media_type_id();

    $tmpl_data{type_chooser} = $self->_media_types_popup_menu();

    # Build category chooser
    my $category_id = $q->param('category_id');
    $q->param('category_id', $m->category_id) unless ($category_id);
    my $category_chooser = category_chooser(
        query      => $q,
        name       => 'category_id',
        formname   => 'edit_media_form',
        may_edit   => 1,
        persistkey => pkg('Media'),
    );
    $tmpl_data{category_chooser} = $category_chooser;

    # If we have a filename, show it.
    $tmpl_data{file_size} = sprintf("%.1fk", ($m->file_size() / 1024))
      if ($tmpl_data{filename} = $m->filename());

    # Set up Contributors
    my @contribs      = ();
    my %contrib_types = pkg('Pref')->get('contrib_type');
    foreach my $c ($m->contribs()) {
        my %contrib_row = (
            first => $c->first(),
            last  => $c->last(),
            type  => localize($contrib_types{$c->selected_contrib_type()}),
        );
        push(@contribs, \%contrib_row);
    }
    $tmpl_data{contribs} = \@contribs;

    # add the tags
    $tmpl_data{tags} = join(', ', $m->tags);

    # Handle simple scalar fields
    my @m_fields = qw(
      title
      caption
      copyright
      alt_tag
      notes
    );

    foreach my $mf (@m_fields) {
        $tmpl_data{$mf} = $m->$mf();
    }

    # Persist data for return from view in "return_params"
    $tmpl_data{return_params} = $self->make_return_params('rm', 'edit_uuid');

    # Send data back to caller for inclusion in template
    return \%tmpl_data;
}

# Given a media object, $m, return a hashref with all the data needed
# for the view template
sub make_media_view_tmpl_data {
    my $self = shift;
    my $m    = shift;

    my $q         = $self->query();
    my %tmpl_data = ();

    $tmpl_data{media_id} = $m->media_id();

    my $thumbnail_path = $m->thumbnail_path(relative => 1) || '';
    $tmpl_data{thumbnail_path} = $thumbnail_path;

    $tmpl_data{url} = format_url(
        url    => $m->url(),
        class  => 'media-preview-link',
        name   => "media_$tmpl_data{media_id}",
        length => 50
    );

    $tmpl_data{published_version} = $m->published_version();

    $tmpl_data{version} = $m->version();

    # Display media type name
    my %media_types   = pkg('Pref')->get('media_type');
    my $media_type_id = $m->media_type_id();
    $tmpl_data{type} = localize($media_types{$media_type_id}) if ($media_type_id);

    # Display category
    my $category_id = $m->category_id();
    my ($category) = pkg('Category')->find(category_id => $category_id);
    $tmpl_data{category} = format_url(
        url    => $category->url(),
        length => 50
    );

    # If we have a filename, show it.
    $tmpl_data{file_size} = sprintf("%.1fk", ($m->file_size() / 1024))
      if ($tmpl_data{filename} = $m->filename());

    # Set up Contributors
    my @contribs      = ();
    my %contrib_types = pkg('Pref')->get('contrib_type');
    foreach my $c ($m->contribs()) {
        my %contrib_row = (
            first => $c->first(),
            last  => $c->last(),
            type  => localize($contrib_types{$c->selected_contrib_type()}),
        );
        push(@contribs, \%contrib_row);
    }
    $tmpl_data{contribs}      = \@contribs;
    $tmpl_data{return_script} = $q->param('return_script');

    # Display creation_date
    my $creation_date = $m->creation_date();
    $tmpl_data{creation_date} = $creation_date->strftime(localize('%m/%d/%Y %I:%M %p'));

    # add the tags
    $tmpl_data{tags} = join(', ', $m->tags);

    # Handle simple scalar fields
    my @m_fields = qw(
      title
      caption
      copyright
      alt_tag
      notes
    );

    foreach my $mf (@m_fields) {
        $tmpl_data{$mf} = $m->$mf();
    }

    # CodePress tmppl_vars: is_text, text_content & text_type
    if ($m->is_text) {
        $tmpl_data{is_text} = 1;

        # populate template with the file's contents
        open(FILE, $m->file_path)
          or croak "unable to open media file " . $m->file_path . " - $!";
        my $text_content = join '', <FILE>;
        close FILE;
        $tmpl_data{text_content} = $text_content;

        # populate template with the syntax-highlighting "language"
        my $text_type     = 'html';                                     # the default
        my $extension     = $m->file_path =~ /\.([^\.]+)$/ ? $1 : '';
        my %extension_map = (
            js  => 'javascript',
            css => 'css',
            php => 'php',
            pl  => 'perl',
        );
        $text_type = $extension_map{$extension} if $extension_map{$extension};
        debug("CodePress text type: $text_type");
        $tmpl_data{text_type}     = $text_type;
        $tmpl_data{use_codepress} = pkg('MyPref')->get('syntax_highlighting');
    }

    # Store any special return params
    my %return_params = $q->param('return_params');
    $tmpl_data{return_params_loop} =
      [map { {name => $_, value => $return_params{$_}} } keys %return_params];

    $tmpl_data{can_edit} = 1
      unless (not($m->may_edit)
        or ($m->checked_out and ($m->checked_out_by ne $ENV{REMOTE_USER}))
        or $m->retired
        or $m->trashed);

    # Send data back to caller for inclusion in template
    return \%tmpl_data;
}

# Given an array of parameter names, return HTML hidden
# input fields suitible for setting up a return link
sub make_return_params {
    my $self              = shift;
    my @return_param_list = (@_);

    my $q = $self->query();

    my @return_params_hidden = ();
    foreach my $hrp (@return_param_list) {

        # Store param name
        push(
            @return_params_hidden,
            $q->hidden(
                -name     => 'return_params',
                -value    => $hrp,
                -override => 1
            )
        );

        # set the value either to a CGI param, what was previously in the
        # session, or nothing.
        my $pval = $q->param($hrp);
        $pval = $session{KRANG_PERSIST}{pkg('Media')}{$hrp} unless defined($pval);
        $pval = '' unless defined($pval);

        push(
            @return_params_hidden,
            $q->hidden(
                -name     => 'return_params',
                -value    => $pval,
                -override => 1
            )
        );
    }

    my $return_params = join("\n", @return_params_hidden);
    return $return_params;
}

# Given a persist_vars and find_params, return the pager object
sub make_pager {
    my $self = shift;
    my ($persist_vars, $find_params, $show_thumbnails, $retired) = @_;

    # read-only users don't see checkbox column....
    my %user_permissions = (pkg('Group')->user_asset_permissions);
    my $read_only = ($user_permissions{media} eq 'read-only');

    my @columns = qw(
      pub_status
      media_id
      thumbnail
      title
      url
      creation_date
      commands_column
      status
    );

    push @columns, 'checkbox_column' unless $read_only;

    my %column_labels = (
        pub_status      => '',
        media_id        => 'ID',
        thumbnail       => 'Thumbnail',
        title           => 'Title',
        url             => 'URL',
        creation_date   => 'Date',
        commands_column => '',
        status          => 'Status',
    );

    # Hide thumbnails
    unless ($show_thumbnails) {
        splice(@columns, 2, 1);
        delete($column_labels{thumbnail});
    }

    my $q     = $self->query();
    my $pager = pkg('HTMLPager')->new(
        cgi_query               => $q,
        persist_vars            => $persist_vars,
        use_module              => pkg('Media'),
        find_params             => $find_params,
        columns                 => \@columns,
        column_labels           => \%column_labels,
        columns_sortable        => [qw( media_id title url creation_date )],
        default_sort_order_desc => 1,
        columns_hidden          => [qw( status )],
        row_handler =>
          sub { $self->find_media_row_handler($show_thumbnails, @_, retired => $retired); },
        id_handler => sub { return $_[0]->media_id },
    );

    return $pager;
}

# Pager row handler for media find run-modes
sub find_media_row_handler {
    my $self = shift;
    my ($show_thumbnails, $row, $media, $pager, %args) = @_;

    my $list_retired        = $args{retired};
    my $may_edit_and_retire = (
        not($media->may_edit)
          or (  ($media->checked_out)
            and ($media->checked_out_by ne $ENV{REMOTE_USER}))
    ) ? 0 : 1;

    # media_id
    my $media_id = $media->media_id();
    $row->{media_id} = $media_id;

    # format url to fit on the screen and to link to preview
    $row->{url} = format_url(
        url   => $media->url(),
        class => 'media-preview-link',
        name  => "media_$media_id",
    );

    # title
    $row->{title} = $self->query->escapeHTML($media->title);

    # thumbnail
    if ($show_thumbnails) {
        my $thumbnail_path = $media->thumbnail_path(relative => 1);
        if ($thumbnail_path) {
            $row->{thumbnail} = qq|
              <a href="" class="media-preview-link" name="media_$media_id">
                <img alt="" src="$thumbnail_path" class="thumbnail">
              </a>
            |;
        } else {
            $row->{thumbnail} = "&nbsp;";
        }
    }

    # creation_date
    my $tp = $media->creation_date();
    $row->{creation_date} =
      (ref($tp)) ? $tp->strftime(localize('%m/%d/%Y %I:%M %p')) : localize('[n/a]');

    # pub_status
    $row->{pub_status} = $media->published() ? '<b>' . localize('P') . '</b>' : '&nbsp;';

    # Buttons: all may view
    my %txt = map { $_ => localize($_) } (qw(View Detail Log Unretire Edit Retire));
    my $button = 'class="button" type="button"';
    $row->{commands_column} = qq|
        <ul>
          <li class="menu">
            <input value="$txt{View} &#9660;" onclick="return false;" $button>
            <ul>
              <li><a href="javascript:view_media($media_id)">$txt{Detail}</a></li>
              <li><a href="javascript:view_log($media_id)">$txt{Log}</a></li>
            </ul>
          </li>
    |;

    # short-circuit for trashed media
    if ($media->trashed) {
        $pager->column_display(status => 1);
        $row->{status}          = localize('Trash');
        $row->{checkbox_column} = "&nbsp;";
        return 1;
    }

    # short-circuit for read_only media
    if ($media->read_only) {
        $pager->column_display(status => 1);
        $row->{status}          = localize('Read-Only');
        $row->{checkbox_column} = "&nbsp;";
        return 1;
    }

    # Buttons and status continued
    if ($list_retired) {

        # Retired Media screen
        if ($media->retired) {
            $row->{commands_column} .=
              qq|<li><input value="$txt{Unretire}" onclick="unretire_media($media_id)" $button></li>|
              if $may_edit_and_retire;
            $row->{pub_status} = '';
            $row->{status}     = '&nbsp;';
        } else {
            $pager->column_display(status => 1);
            if ($media->checked_out) {
                $row->{status} =
                    localize('Live') 
                  . '<br />'
                  . localize('Checked out by') . '<b>'
                  . (pkg('User')->find(user_id => $media->checked_out_by))[0]->login . '</b>';
            } else {
                $row->{status} = localize('Live');
            }
            $row->{pub_status} = $media->published ? ('<b>' . localize('P') . '</b>') : '&nbsp;';
        }
    } else {

        # Find Media screen
        $pager->column_display(status => 1);
        if ($media->retired) {

            # Media is retired
            $row->{pub_status}      = '';
            $row->{status}          = localize('Retired');
            $row->{checkbox_column} = "&nbsp;";
        } else {

            # Media is not retired: Maybe we may edit and retire
            $row->{commands_column} .= qq|
                <li><input value="$txt{Edit}" onclick="edit_media($media_id)" $button></li>
                <li><input value="$txt{Retire}" onclick="retire_media($media_id)" $button></li>
            | if $may_edit_and_retire;
            if ($media->checked_out) {
                $row->{status} =
                  localize('Checked out by') . " <b>"
                  . (pkg('User')->find(user_id => $media->checked_out_by))[0]->login . '</b>';
            } else {
                $row->{status} = '&nbsp;';
            }
            $row->{pub_status} = $media->published ? ('<b>' . localize('P') . '</b>') : '&nbsp;';
        }
    }

    unless ($may_edit_and_retire) {
        $row->{checkbox_column} = "&nbsp;";
    }

    $row->{commands_column} .= '</ul>';

}

# Actually save the media.  Catch exceptions
# Return error hash if errors are encountered
sub do_save_media {
    my $self = shift;
    my $m    = shift;

    # Attempt to write back to database
    eval { $m->save() };

    # Is it a dup?
    if ($@) {
        if (ref($@) and $@->isa('Krang::Media::DuplicateURL')) {
            if ($self->query->param('created_empty_file')) {
                $m->filename('');
                clear_messages;
                add_alert('duplicate_url_without_file');
            } else {
                add_alert('duplicate_url');
            }
            return (duplicate_url => 1);
        } elsif (ref($@) and $@->isa('Krang::Media::NoCategoryEditAccess')) {

            # User tried to save to a category to which he doesn't have access
            my $category_id = $@->category_id
              || croak("No category_id on pkg('Media::NoCategoryEditAccess') exception");
            my ($cat) = pkg('Category')->find(category_id => $category_id);
            add_alert(
                'no_category_access',
                url => $cat->url,
                id  => $category_id
            );
            return (error_category_id => 1);
        } else {

            # Not our error!
            die($@);
        }
    }

    # If everything is OK, return an empty array
    return ();
}

sub autocomplete {
    my $self = shift;
    return autocomplete_values(
        table  => 'media',
        fields => [qw(media_id title caption alt_tag filename)],
    );
}

=item retire

Move media to the retire and return to the Find Media screen.

=cut

sub retire {
    my $self = shift;
    my $q    = $self->query;

    my $media_id = $q->param('media_id');

    croak("No media_id found in CGI params when archiving media.")
      unless $media_id;

    # load media from DB and retire it
    my ($media) = pkg('Media')->find(media_id => $media_id);

    croak("Unable to load Media '" . $media_id . "'.")
      unless $media;

    $media->retire();

    add_message('media_retired', id => $media_id, url => $media->url);

    $q->delete('media_id');

    return $self->find();
}

=item unretire

Move media from retire back to live. If a DuplicateURL conflict
occurs, leave the media retired and alert the user.

=cut

sub unretire {
    my $self = shift;
    my $q    = $self->query;

    my $media_id = $q->param('media_id');

    croak("No media_id found in CGI params when trying to unretire media.")
      unless $media_id;

    # load media from DB and unretire it
    my ($media) = pkg('Media')->find(media_id => $media_id);

    croak("Unable to load media '" . $media_id . "'.")
      unless $media;

    eval { $media->unretire() };

    if ($@ and ref($@)) {
        if ($@->isa('Krang::Media::DuplicateURL')) {
            add_alert(
                'duplicate_url_on_unretire',
                id       => $media_id,
                other_id => $@->media_id,
                url      => $media->url
            );
        } elsif ($@->isa('Krang::Media::NoEditAccess')) {

            # param tampering
            # or perhaps a permission change
            add_alert('access_denied_on_unretire', id => $media_id, url => $media->url);
        }
        return $self->list_retired;
    }

    add_message('media_unretired', id => $media_id, url => $media->url);

    return $self->list_retired;
}

sub save_and_transform_image {
    my $self = shift;

    my $q = $self->query();

    # Update media object
    $self->_save;

    return $self->transform_image;
}

sub transform_image {
    my $self        = shift;
    my $q           = $self->query();
    my $m           = $self->get_edit_object();
    my $edit_uuid   = $self->edit_uuid;
    my $apply_trans = $q->param('apply_transform');
    my ($imager, $url);

    if ($apply_trans) {
        $imager = $self->_do_apply_transform($m, $q);

        # change the file_path into a relative url
        $url = abs2rel($session{$edit_uuid}{'image_transform_tmp_file'}, KrangRoot);

    } else {
        $self->_clear_image_transform_session();
        $imager = Imager->new();
        $imager->open(file => $m->file_path) or croak $imager->errstr();
        $url = $m->file_path(relative => 1);
        $session{$edit_uuid}{'image_transform_actions'} = {};
    }

    my $t = $self->load_tmpl('transform_image.tmpl');
    $t->param(
        media_id        => $m->media_id,
        title           => $m->title,
        url             => $url,
        original_width  => $imager->getwidth,
        original_height => $imager->getheight,
    );
    return $t->output;
}

sub _do_apply_transform {
    my ($self, $media, $query) = @_;
    my $imager    = Imager->new();
    my $edit_uuid = $self->edit_uuid;

    # do our work on a temp file
    my $tmp_dir = tempdir(CLEANUP => 0, DIR => catdir(KrangRoot, 'tmp'));
    my $file_path = catfile($tmp_dir, $media->filename);

    # copy the old file there
    my $old_file = $session{$edit_uuid}{'image_transform_tmp_file'} || $media->file_path;
    copy($old_file, $file_path) or die "Could not copy file $old_file to $file_path: $!\n";
    $session{$edit_uuid}{'image_transform_tmp_file'} = $file_path;
    $imager->open(file => $file_path) or croak $imager->errstr();

    # RESIZE
    my $new_width  = $query->param('new_width');
    my $new_height = $query->param('new_height');
    if ($new_width || $new_height) {
        add_message('image_scaled', width => $new_width, height => $new_height);
        $imager = $imager->scale(xpixels => $new_width, ypixels => $new_height, type => 'nonprop');
        $session{$edit_uuid}{'image_transform_actions'}->{resize} = 1;
    }

    # CROP
    my %crop = map { $_ => $query->param("crop_$_") } qw(x y width height);
    if ($crop{x} || $crop{y} || $crop{width} || $crop{width}) {
        $imager = $imager->crop(
            left   => $crop{x},
            top    => $crop{y},
            width  => $crop{width},
            height => $crop{height}
        );
        add_message('image_cropped', width => $imager->getwidth, height => $imager->getheight);
        $session{$edit_uuid}{'image_transform_actions'}->{crop} = 1;
    }

    # ROTATE
    if (my $direction = $query->param('rotate_direction')) {
        my $degress = $direction eq 'r' ? 90 : -90;
        $imager = $imager->rotate(degrees => $degress);
        add_message("image_rotated_$direction");
        $session{$edit_uuid}{'image_transform_actions'}->{rotate} = 1;
    }

    # FLIP
    if (my $direction = $query->param('flip_direction')) {
        $imager->flip(dir => $direction);
        add_message("image_flipped_$direction");
        $session{$edit_uuid}{'image_transform_actions'}->{flip} = 1;
    }

    # now save it to a tmp place
    $imager->write(file => $file_path);
    return $imager;
}

sub save_image_transform {
    my $self      = shift;
    my $m         = $self->get_edit_object();
    my $edit_uuid = $self->edit_uuid;
    my $imager    = $self->_do_apply_transform($m, $self->query);

    # save changes
    $m->upload_file(filepath => $session{$edit_uuid}{'image_transform_tmp_file'});
    $m->save();
    add_message('image_transform_saved');

    # now record the history of what was done
    foreach my $action (keys %{$session{$edit_uuid}{'image_transform_actions'}}) {
        add_history(object => $m, action => $action);
    }

    return $self->edit;
}

sub cancel_image_transform {
    my $self = shift;
    $self->_clear_image_transform_session();
    add_message("image_transform_canceled");
    return $self->edit;
}

sub _clear_image_transform_session {
    my $self      = shift;
    my $edit_uuid = $self->edit_uuid;

    # clear the tmp file
    if (my $file = $session{$edit_uuid}{'image_transform_tmp_file'}) {
        unlink $file if -e $file;
        delete $session{$edit_uuid}{'image_transform_tmp_file'};
    }

    # clear any history actions
    delete $session{$edit_uuid}{'image_transform_actions'};
}

# The "_media_types_popup_menu" method creates the popup menu for
# the 'media_type_id' of Media objects.
sub _media_types_popup_menu {
    my ($self, %args) = @_;
    my $search = $args{search} ? 1 : 0;
    my $q = $self->query();

    # is there a certain type that is selected?
    my $type_id;
    if ($search) {
        $type_id = $session{KRANG_PERSIST}{pkg('Media')}{search_media_type_id};
    } else {
        if (my $current_media = eval { $self->get_edit_object }) {
            $type_id = $current_media->media_type_id;
        }
        $type_id ||= $session{KRANG_PERSIST}{pkg('Media')}{media_type_id};
    }

    # Build type drop-down
    my %media_types = pkg('Pref')->get('media_type');
    %media_types = map { $_ => localize($media_types{$_}) } keys %media_types;
    my @media_type_ids = ("", sort { $media_types{$a} cmp $media_types{$b} } keys(%media_types));

    return $q->popup_menu(
        -name => ($search ? 'search_media_type_id' : 'media_type_id'),
        -values  => \@media_type_ids,
        -labels  => \%media_types,
        -default => $type_id,
    );
}

# overload load_tmpl so that the edit_uuid is set
sub load_tmpl {
    my $self = shift;
    my $tmpl = $self->SUPER::load_tmpl(@_);
    if (my $edit_uuid = $self->edit_uuid) {
        $tmpl->param(edit_uuid => $edit_uuid) if $tmpl->query(name => 'edit_uuid');
    }
    return $tmpl;
}

sub _get_element        { shift->get_edit_object->element }
sub _get_script_name    { "media.pl" }
sub edit_object_package { pkg('Media') }

1;

=back

=cut
