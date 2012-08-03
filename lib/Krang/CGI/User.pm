package Krang::CGI::User;

=head1 NAME

Krang::CGI::User -
Abstract of web application....


=head1 SYNOPSIS

  use Krang::ClassLoader 'CGI::User';
  my $app = pkg('CGI::User')->new();
  $app->run();


=head1 DESCRIPTION

Overview of functionality and purpose of
web application module Krang::CGI::User...

=cut

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => qw/CGI/;

use Carp qw(verbose croak);
use Krang::ClassLoader 'History';
use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader Log     => qw/critical debug info/;
use Krang::ClassLoader Widget  => qw/autocomplete_values/;
use Krang::ClassLoader Message => qw(add_message add_alert get_alerts clear_alerts);
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'User';
use Krang::ClassLoader 'PasswordHandler';
use Krang::ClassLoader Localization => qw(localize);

# query fields to delete
use constant DELETE_FIELDS => (
    pkg('User')->USER_RW,
    qw(confirm_password
      new_password
      password
      current_group_ids)
);

##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
    my $self = shift;

    $self->start_mode('search');

    $self->run_modes(
        [
            qw/
              add
              cancel_add
              save_add
              save_stay_add
              delete
              delete_selected
              edit
              cancel_edit
              save_edit
              save_stay_edit
              search
              autocomplete
              /
        ]
    );

    $self->tmpl_path('User/');

}

##############################
#####  RUN-MODE METHODS  #####
##############################

=head1 INTERFACE



=head1 RUN MODES

=over 4


=item * add

Displays the "Add User" screen by means of which a new user object can be added
to the system.

=cut

sub add {
    my $self        = shift;
    my %ui_messages = @_;
    my $q           = $self->query();
    my $t           = $self->load_tmpl(
        "edit_view.tmpl",
        associate         => $q,
        die_on_bad_params => 0
    );

    $t->param(add_mode => 1);
    $t->param(%ui_messages) if %ui_messages;

    # make new User object
    my $user = pkg('User')->new(login => '', password => '');

    # store object in session
    $session{EDIT_USER} = $user;

    $t->param($self->get_user_params($user));

    $t->param(password_spec => pkg('PasswordHandler')->_password_spec);

    return $t->output();
}

=item * cancel_add

Cancels edit of user object on "Add User" screen and returns to 'search' run
mode.

=cut

sub cancel_add {
    my $self = shift;

    my $q = $self->query();

    add_message('message_add_cancelled');

    return $self->search();
}

=item * save_add

Saves user object visible on 'add' screen.  Returns to 'search' run mode.

It retrieves the user from the session object and overwrites the fields of this
object with the query parameters passed to this run mode, with the exception of
the 'user_id'.

The 'new_password' field and 'confirm_password' fields are compared for
equality is they are equal the value in 'new_password' will be MD5'd and stored
in the password field, otherwise the end-user will be returned to the 'edit'
screen.

The password will also be checked by the C<PasswordHandler> and if validation
fails, the user will be returned to the 'add' screen.

=cut

sub save_add {
    my $self = shift;

    my $q = $self->query();

    my %errors = $self->validate_user();

    # Return to edit screen if there are errors
    return $self->add(%errors) if %errors;

    # Get user from session
    my $user = $session{EDIT_USER} || 0;
    croak("Can't retrieve EDIT_USER from session") unless $user;

    # now validate the password
    my $valid = pkg('PasswordHandler')->check_pw(
        $q->param('new_password'),
        $user->login, $q->param('email'),
        $q->param('first_name'),
        $q->param('last_name'),
    );
    unless ($valid) {
        $q->param(errors => 1);
        return $self->add();
    }

    %errors = $self->update_user($user);
    return $self->access_forbidden if $errors{'tampered_gids'};
    return $self->edit(%errors)    if %errors;

    $q->delete(DELETE_FIELDS);

    add_message('message_user_saved');

    return $self->search();
}

=item * save_stay_add

Saves user object to the database and redirects to the "Edit User" screen.

This mode function just like the 'save_add' run mode except for redirecting
the user to 'edit' run mode.

=cut

sub save_stay_add {
    my $self = shift;

    my $q = $self->query();

    my %errors = $self->validate_user();

    # Return to edit screen if there are errors
    return $self->add(%errors) if %errors;

    # Get user from session
    my $user = $session{EDIT_USER} || 0;
    croak("Can't retrieve EDIT_USER from session") unless $user;

    # now validate the password
    my $valid = pkg('PasswordHandler')->check_pw(
        $q->param('new_password'),
        $user->login, $q->param('email'),
        $q->param('first_name'),
        $q->param('last_name'),
    );
    unless ($valid) {
        $q->param(errors => 1);
        return $self->add();
    }

    %errors = $self->update_user($user);
    return $self->access_forbidden if $errors{'tampered_gids'};
    return $self->add(%errors)     if %errors;

    # preserve, set vals for 'edit' run mode
    $q->delete(DELETE_FIELDS);
    $q->param(user_id => $user->user_id());
    $q->param(rm      => 'edit');

    add_message('message_user_saved');

    return $self->edit();
}

=item * delete

Deletes the user from 'edit' screen and redirects to 'search' run mode.

It expects a 'user_id' query param.

=cut

sub delete {
    my $self = shift;

    my $q       = $self->query();
    my $user_id = $q->param('user_id');
    return $self->search() unless $user_id;

    my ($logged_in_user) = pkg('User')->find(user_id => $ENV{REMOTE_USER});
    $self->_redirect_to_login() unless $logged_in_user;

    unless ($logged_in_user->may_delete_user($user_id)) {
        my ($u) = pkg('User')->find(user_id => $user_id);
        add_alert('may_not_delete_user', user => $u->display_name);
        return $self->edit;
    }

    eval { pkg('User')->delete($user_id); };

    if ($@) {
        if (ref $@ && $@->isa('Krang::User::Dependency')) {
            critical(
                "Unable to delete user '$user_id': objects are " . "checked out by this user.");
            my ($user) = pkg('User')->find(user_id => $user_id);
            add_alert(
                'error_deletion_failure',
                login   => $user->display_name,
                user_id => $user->user_id,
            );
            return $self->search();
        } else {
            croak($@);
        }
    }

    # suicidal?
    if ($user_id == $ENV{REMOTE_USER}) {
        add_alert('user_suicide');
        return $self->_redirect_to_login();
    }

    add_message('message_deleted');

    return $self->search();
}

=item * delete_selected

Deletes User objects selected from the 'search' screen.  Returns to 'search'
afterwards.

This mode expects the 'krang_pager_rows_checked' param which should contain an
array of 'user_id's signifying the user objects to be deleted.

=cut

sub delete_selected {
    my $self = shift;

    my $q = $self->query();
    my %user_delete_list = map { $_ => 1 } ($q->param('krang_pager_rows_checked'));
    $q->delete('krang_pager_rows_checked');

    # return to search if no ids were passed
    return $self->search() unless %user_delete_list;

    my ($current_user) = pkg('User')->find(user_id => $ENV{REMOTE_USER});
    my $num_users_deleted = 0;
    my @users_not_deleted = ();

    # destroy users
    for my $u (keys %user_delete_list) {

        # list of users we may not delete
        unless ($current_user->may_delete_user($u)) {

            # CGI param tampering, remember it
            push @users_not_deleted, pkg('User')->find(user_id => $u);
            next;
        }

        eval { pkg('User')->delete($u); };

        if ($@) {
            if (ref $@ && $@->isa('Krang::User::Dependency')) {
                critical("Unable to delete user '$u': objects are checked " . "out by this user.");
                my ($user) = pkg('User')->find(user_id => $u);
                add_alert(
                    'error_deletion_failure',
                    login   => $user->display_name,
                    user_id => $user->user_id,
                );
                delete $user_delete_list{$u};
                next;
            } else {
                croak($@);
            }
        } else {
            $num_users_deleted++;
        }
    }

    # suicidal?
    my $suicide = 0;
    if ($user_delete_list{$ENV{REMOTE_USER}}) {
        add_alert('user_suicide');
        $suicide = 1;
    }

    $self->add_message_for_delete_selected($num_users_deleted, @users_not_deleted)
      if $num_users_deleted;
    return $suicide ? $self->_redirect_to_login() : $self->search();
}

=item * edit

Display a screen allowing the end-user to edit the User object selected from
the 'search' screen.

This run mode expects a 'user_id' query param and it will croak if it's missing
or invalid.

N.B - propagate query params supercede object field values in populating form
fields, so errant values are preserved for correction.

=cut

sub edit {
    my $self        = shift;
    my %ui_messages = @_;
    my $q           = $self->query();
    my $user_id     = $q->param('user_id');
    my $user        = $session{EDIT_USER};

    if ($user_id) {
        ($user) = pkg('User')->find(user_id => $user_id);
        $session{EDIT_USER} = $user;
    }
    croak(__PACKAGE__ . "->edit(): No pkg('User') object found matching " . "user_id '$user_id'")
      unless defined $user;

    my $t = $self->load_tmpl(
        "edit_view.tmpl",
        associate         => $q,
        die_on_bad_params => 0
    );

    $t->param(%ui_messages) if %ui_messages;

    $t->param($self->get_user_params($user));

    $t->param(password_spec => pkg('PasswordHandler')->_password_spec);

    return $t->output();
}

=item * cancel_edit

Cancels edit of user object on "Edit User" screen and returns to 'search' run
mode.

=cut

sub cancel_edit {
    my $self = shift;

    my $q = $self->query();

    add_message('message_save_cancelled');

    return $self->search();
}

=item * save_edit

Updates user object visible on 'edit' screen.  Returns to 'search' run mode.

It retrieves the user from the session object and overwrites the fields of this
object with the query parameters passed to this run mode, with the exception of
the 'user_id'.

The 'new_password' field and 'confirm_password' fields are compared for
equality is they are equal the value in 'new_password' will be MD5'd and stored
in the password field, otherwise the end-user will be returned to the 'edit'
screen.

=cut

sub save_edit {
    my $self = shift;

    my $q = $self->query();

    my %errors = $self->validate_user();

    # Return to edit screen if there are errors
    return $self->edit(%errors) if %errors;

    # Get user from session
    my $user = $session{EDIT_USER} || 0;
    croak("Can't retrieve EDIT_USER from session") unless $user;

    # now validate the password
    if ($q->param('new_password')) {
        my $valid = pkg('PasswordHandler')->check_pw(
            $q->param('new_password'),
            $user->login,
            $q->param('email')      || $user->email,
            $q->param('first_name') || $user->first_name,
            $q->param('last_name')  || $user->last_name,
        );
        unless ($valid) {
            $q->param(errors => 1);
            return $self->edit();
        }
    }

    %errors = $self->update_user($user);
    return $self->access_forbidden if $errors{'tampered_gids'};
    return $self->edit(%errors)    if %errors;

    $q->delete(DELETE_FIELDS);

    add_message('message_user_saved');

    return $self->search();
}

=item * save_stay_edit

Updates user object in database and returns/remains on the "Edit User" screen.

This mode function just like the 'save_edit' run mode except for redirecting
the user to 'edit' run mode.

=cut

sub save_stay_edit {
    my $self = shift;

    my $q = $self->query();

    my %errors = $self->validate_user();

    # Return to edit screen if there are errors
    return $self->edit(%errors) if %errors;

    # Get user from session
    my $user = $session{EDIT_USER} || 0;
    croak("Can't retrieve EDIT_USER from session") unless $user;

    # now validate the password
    if ($q->param('new_password')) {
        my $valid = pkg('PasswordHandler')->check_pw(
            $q->param('new_password'),
            $user->login,
            $q->param('email')      || $user->email,
            $q->param('first_name') || $user->first_name,
            $q->param('last_name')  || $user->last_name,
        );
        unless ($valid) {
            $q->param(errors => 1);
            return $self->edit();
        }
    }

    %errors = $self->update_user($user);
    return $self->access_forbidden if $errors{'tampered_gids'};
    return $self->edit(%errors)    if %errors;

    # preserve, set vals for 'edit' run mode
    $q->delete(DELETE_FIELDS);
    $q->param(user_id => $user->user_id());
    $q->param(rm      => 'edit');

    add_message('message_user_saved');

    return $self->edit();
}

=item * search

Display a list of all users or those matching the supplied search criteria.

This run mode accepts the optional parameter "search_filter" which is expected
to contain a text string which will in turn be used to query users.

=cut

sub search {
    my $self = shift;

    my $q = $self->query();

    my $t = $self->load_tmpl(
        "list_view.tmpl",
        associate         => $q,
        loop_context_vars => 1
    );

    # simple search
    my $search_filter = $q->param('search_filter');
    if (!defined $search_filter) {
        $search_filter = $session{KRANG_PERSIST}{pkg('User')}{search_filter}
          || '';
    }

    # setup pager
    my $pager = pkg('HTMLPager')->new(
        cgi_query    => $q,
        persist_vars => {
            rm            => 'search',
            search_filter => $search_filter,
        },
        use_module  => pkg('User'),
        find_params => {
            simple_search => $search_filter,
            hidden        => 0,
        },
        columns       => ['login', 'first', 'last', 'command_column', 'checkbox_column',],
        column_labels => {
            login => 'User Name',
            first => 'First Name',
            last  => 'Last Name',
        },
        columns_sortable => [qw(login last first)],
        columns_sort_map => {
            first => 'first_name',
            last  => 'last_name',
        },
        command_column_commands => [qw(edit_user)],
        command_column_labels   => {edit_user => 'Edit'},
        row_handler             => sub { $self->search_row_handler(@_) },
        id_handler              => sub { return $_[0]->user_id },
    );

    # get pager output
    $t->param(
        pager_html    => $pager->output,
        search_filter => $search_filter,
    );

    # get counter params
    $t->param(row_count => $pager->row_count());

    return $t->output();
}

# Construct param hashref to be used for edit template output
sub get_user_params {
    my $self = shift;
    my $user = shift;
    my $q    = $self->query();
    my %user_tmpl;

    # only show groups we are allowed to manage
    my %find_params = ();
    if (pkg('Group')->user_admin_permissions('admin_users_limited')) {
        $find_params{group_ids} = [pkg('User')->current_user_group_ids];
    }

    # build hash of Krang::Group permission groups...
    my %user_groups = map { $_->group_id => $_->name } pkg('Group')->find(%find_params);

    # make group_ids multi-select
    my @cgids =
        $q->param('errors')
      ? $q->param('current_group_ids')
      : grep { $user_groups{$_} } $user->group_ids;
    my %cgids = map { $_, 1 }
      sort { lc $user_groups{$a} cmp lc $user_groups{$b} } @cgids;
    my @pgids = grep { not exists $cgids{$_} }
      sort { lc $user_groups{$a} cmp lc $user_groups{$b} } keys %user_groups;
    push @{$user_tmpl{possible_group_ids}}, {id => $_, name => $user_groups{$_}} for @pgids;
    push @{$user_tmpl{current_group_ids}},  {id => $_, name => $user_groups{$_}} for @cgids;

    # loop through User fields
    if ($q->param('errors')) {
        $user_tmpl{$_} = $q->param($_) for pkg('User')->USER_RW;
        $q->delete('errors');
    }
    else {
        $user_tmpl{$_} = $user->$_ for pkg('User')->USER_RW;
    }

    delete $user_tmpl{hidden};
    return \%user_tmpl;
}

# Update the user object with the values in the CGI query
sub update_user {
    my $self = shift;
    my $user = shift;
    my $q    = $self->query();

    # overwrite object fields
    $user->$_($q->param($_) ? $q->param($_) : undef)
      for grep { $_ ne 'hidden' and $_ ne 'password_changed' and $_ ne 'force_pw_change' }
      pkg('User')->USER_RW;

    # set password if we've been handed one
    my $pass = $q->param('password') || '';
    $user->password($pass) unless $pass eq '';

    # handle group ids
    my %preserve_gids = ();    # groups the current user may not handle
    my %may_manage_gids  = map { $_ => 1 } pkg('User')->current_user_group_ids;
    my %incoming_gids    = map { $_ => 1 } $q->param('current_group_ids');
    my @target_user_gids = $user->group_ids;

    # be careful when having limited user management perms
    if (pkg('Group')->user_admin_permissions('admin_users_limited')) {

        # preserve groups the current user is not allowed to handle
        %preserve_gids = map { $_ => 1 }
          grep { not $may_manage_gids{$_} } @target_user_gids;

        # prevent current user from tampering current_group_ids param
        return ('tampered_gids' => 1)
          if grep { not $may_manage_gids{$_} } keys %incoming_gids;
    }

    # combine the incoming and the preserved gids
    my %gids = (%incoming_gids, %preserve_gids);

    if (%gids) {
        $user->group_ids(keys %gids);
    } else {
        $user->group_ids_clear();
    }

    # attempt to save
    eval { $user->save() };

    # Did we get a duplicate exception
    if ($@) {
        my %errors;
        if (ref $@ && $@->isa('Krang::User::Duplicate')) {
            my %dupes = %{$@->duplicates};
            for my $v (values %dupes) {
                for (@$v) {
                    my $error = "duplicate_" . $_;
                    $errors{$error} = 1;
                    $q->param('errors', 1);
                    add_alert($error);
                }
            }
            return %errors;
        } elsif (ref $@ && $@->isa('Krang::User::InvalidGroup')) {
            my $ids = $@->group_id;
            my $error =
              (defined $ids && ref $ids)
              ? 'error_invalid_group_id'
              : 'error_null_group';
            $errors{$error} = 1;
            $q->param('errors', 1);
            add_alert($error);
            return %errors;
        } elsif (ref $@ && $@->isa('Krang::User::MissingGroup')) {
            my $error = "error_missing_group";
            $errors{$error} = 1;
            $q->param('errors', 1);
            add_alert($error);
            return %errors;
        } else {

            # it's somebody else's problem :)
            croak($@);
        }
    }

    return ();
}

# Ensure the validity of parameters passed while attempting to save or update
# the user object
# * Enforces the login length requirement (at present 3 characters).
sub validate_user {
    my $self = shift;
    my $q    = $self->query();
    my %errors;

    # login, first, and last cannot be empty; email must be empty or valid
    for (qw/login first_name last_name email/) {
        my $val = $q->param($_);

        if ($_ eq 'email') {
            $errors{error_invalid_email} = 1
              if ($val ne '' && $val !~ /[\w.-]+\@[\w.-]+\.\w+/);
        } else {
            $errors{"error_invalid_$_"} = 1 if ($val eq '' || $val =~ /^\s+$/);

            # check login length
            if ($_ eq 'login') {
                $errors{"error_login_length"} = 1
                  unless (length($val) >= 6 || grep $val eq $_, pkg('User')->SHORT_NAMES);
            }
        }
    }

    my ($mode, $pass, $cpass) = map { $q->param($_) } qw/rm new_password confirm_password/;

    # only check if this is a first time save or if either of the password
    # fields contain a value...
    if ((not $q->param('user_id')) || $pass || $cpass) {

        # validate new_password and confirm_password
        if ($pass eq '') {
            $errors{error_null_password} = 1 if $mode =~ /add/;
            $errors{error_password_mismatch} = 1 if $cpass ne '';
        } elsif ($cpass eq '') {
            $errors{error_password_mismatch} = 1 if $mode =~ /add/;
            $errors{error_password_mismatch} = 1 if $pass ne '';
        } elsif ($pass ne '' || $cpass ne '') {
            if ($pass ne $cpass) {
                $errors{error_password_mismatch} = 1;
            } else {
                $q->param('password', $pass);
            }
        }
    }

    # Add error messages
    add_alert($_) for keys %errors;
    $q->param('errors', 1) if keys %errors;

    return %errors;
}

##############################
#####  PRIVATE METHODS   #####
##############################

# Handles rows for search run mode
sub search_row_handler {
    my ($self, $row, $user, $pager) = @_;
    my $q = $self->query;
    $row->{login} = $q->escapeHTML($user->login);
    $row->{last}  = $q->escapeHTML($user->last_name);
    $row->{first} = $q->escapeHTML($user->first_name);
}

sub autocomplete {
    my $self = shift;
    return autocomplete_values(
        table  => 'user',
        fields => [qw(user_id first_name last_name)],
    );
}

sub add_message_for_delete_selected {
    my ($self, $num_users_deleted, @users_not_deleted) = @_;

    if (@users_not_deleted) {
        if (scalar(@users_not_deleted) == 1) {
            add_alert('may_not_delete_user', user => $users_not_deleted[0]->display_name);
        } else {
            my $u     = pop(@users_not_deleted);
            my $users = $u->display_name;
            while (@users_not_deleted) {
                my $u = pop(@users_not_deleted);
                if (scalar(@users_not_deleted)) {
                    $users .= ', ' . $u->display_name;
                } else {
                    $users .= ' ' . localize('and') . ' ' . $u->display_name;
                }
            }
            add_alert('may_not_delete_users', users => $users);
        }
        if ($num_users_deleted) {
            my $s =
              $num_users_deleted == 1
              ? add_alert('one_user_deleted')
              : add_alert('num_users_deleted', num => $num_users_deleted);
        }
    } else {
        add_message('message_selected_deleted');
    }
}

sub _redirect_to_login {
    my ($self) = shift;

    my $msg = join ' ', get_alerts();
    clear_alerts();

    return $self->redirect_to_login($msg);
}

=back

=head1 TO DO

Instead of failing to delete a user if he has assets checked out, we should
check all of his assets in and then perform the deletion.

=cut

my $quip = <<END;
I do not feel obliged to believe that the same God who has endowed us
with sense, reason, and intellect has intended us to forgo their use.

-- Galileo Galilei
END
