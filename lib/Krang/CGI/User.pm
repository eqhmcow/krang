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
use Krang::ClassLoader Log => qw/critical debug info/;
use Krang::ClassLoader Message => qw(add_message);
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'User';

# query fields to delete
use constant DELETE_FIELDS => (pkg('User')->USER_RW, 
                               qw(confirm_password
                                  new_password
                                  password
                                  current_group_ids));

##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
    my $self = shift;

    $self->start_mode('search');

    $self->run_modes([qw/
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
	/]);

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
    my $self = shift;
    my %ui_messages = @_;
    my $q = $self->query();
    my $t = $self->load_tmpl("edit_view.tmpl", associate => $q);

    $t->param(add_mode => 1);
    $t->param(%ui_messages) if %ui_messages;

    # make new User object
    my $user = pkg('User')->new(login => '', password => '');

    # store object in session
    $session{EDIT_USER} = $user;

    $t->param($self->get_user_params($user));

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

    %errors = $self->update_user($user);
    return $self->edit(%errors) if %errors;

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

    %errors = $self->update_user($user);
    return $self->add(%errors) if %errors;

    # preserve, set vals for 'edit' run mode
    $q->delete(DELETE_FIELDS);
    $q->param(user_id => $user->user_id());
    $q->param(rm => 'edit');

    add_message('message_user_saved');

    return $self->edit();
}


=item * delete

Deletes the user from 'edit' screen and redirects to 'search' run mode.

It expects a 'user_id' query param.

=cut

sub delete {
    my $self = shift;

    my $q = $self->query();
    my $user_id = $q->param('user_id');
    return $self->search() unless $user_id;
    eval {pkg('User')->delete($user_id);};
    if ($@) {
        if (ref $@ && $@->isa('Krang::User::Dependency')) {
            critical("Unable to delete user '$user_id': objects are " .
                     "checked out by this user.");
            my ($user) = pkg('User')->find(user_id => $user_id);
            add_message('error_deletion_failure',
                        login => $user->login,
                        user_id => $user->user_id,);
            return $self->search();
        } else {
            croak($@);
        }
    }

    # suicidal?
    if ($user_id == $ENV{REMOTE_USER}) {
        # delete the session, since it's useless now
        pkg('Session')->delete($ENV{KRANG_SESSION_ID});

        # redirect to login
        $self->header_type('redirect');
        $self->header_props(-url=>'login.pl');
        return "";
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
    my @user_delete_list = ($q->param('krang_pager_rows_checked'));
    $q->delete('krang_pager_rows_checked');

    # return to search if no ids were passed
    return $self->search() unless @user_delete_list;

    # destroy users
    for my $u(@user_delete_list) {
        eval {pkg('User')->delete($u);};
        if ($@) {
            if (ref $@ && $@->isa('Krang::User::Dependency')) {
                critical("Unable to delete user '$u': objects are checked " .
                         "out by this user.");
                my ($user) = pkg('User')->find(user_id => $u);
                add_message('error_deletion_failure',
                            login => $user->login,
                            user_id => $user->user_id,);
                return $self->search();
            } else {
                croak($@);
            }
        }
    }

    add_message('message_selected_deleted');

    return $self->search();
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
    my $self = shift;
    my %ui_messages = @_;
    my $q = $self->query();
    my $user_id = $q->param('user_id');
    my $user = $session{EDIT_USER};

    if ($user_id) {
        ($user) = pkg('User')->find(user_id => $user_id);
        $session{EDIT_USER} = $user;
    }
    croak(__PACKAGE__ . "->edit(): No pkg('User') object found matching " .
          "user_id '$user_id'") unless defined $user;

    my $t = $self->load_tmpl("edit_view.tmpl", associate => $q);

    $t->param(%ui_messages) if %ui_messages;

    $t->param($self->get_user_params($user));

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

    %errors = $self->update_user($user);
    return $self->edit(%errors) if %errors;

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

    %errors = $self->update_user($user);
    return $self->edit(%errors) if %errors;

    # preserve, set vals for 'edit' run mode
    $q->delete(DELETE_FIELDS);
    $q->param(user_id => $user->user_id());
    $q->param(rm => 'edit');

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

    my $t = $self->load_tmpl("list_view.tmpl",
                             associate => $q,
                             loop_context_vars => 1);

    # simple search
    my $search_filter = $q->param('search_filter') || '';

    # setup pager
    my $pager = pkg('HTMLPager')->new(cgi_query => $q,
                                      persist_vars => {
                                                       rm => 'search',
                                                       search_filter =>
                                                       $search_filter,
                                                      },
                                      use_module => 'Krang::User',
                                      find_params =>
                                      {simple_search => $search_filter,
                                       hidden        => 0,
                                      },
                                      columns => [
                                                  'login',
                                                  'last',
                                                  'first',
                                                  'command_column',
                                                  'checkbox_column',
                                                 ],
                                      column_labels => {login => 'User Name',
                                                        last => 'Last Name',
                                                        first => 'First Name',
                                                       },
                                      columns_sortable =>
                                      [qw(login last first)],
                                      columns_sort_map => {
                                                           last => 'last_name',
                                                           first =>
                                                           'first_name'
                                                          },
                                      command_column_commands =>
                                      [qw(edit_user)],
                                      command_column_labels =>
                                      {edit_user => 'Edit'},
                                      row_handler => \&search_row_handler,
                                      id_handler =>
                                      sub {return $_[0]->user_id},
                                     );

    # get pager output
    $t->param(pager_html => $pager->output());

    # get counter params
    $t->param(row_count => $pager->row_count());

    return $t->output();
}


# Construct param hashref to be used for edit template output
sub get_user_params {
    my $self = shift;
    my $user = shift;
    my $q = $self->query();
    my %user_tmpl;

    # build hash of Krang::Group permission groups...
    my %user_groups = map {$_->group_id => $_->name} pkg('Group')->find();

    # make group_ids multi-select
    my @cgids = $q->param('errors') ? $q->param('current_group_ids') :
      $user->group_ids;
    my %cgids = map {$_, 1} @cgids;
    my @pgids = grep {not exists $cgids{$_}} keys %user_groups;
    push @{$user_tmpl{possible_group_ids}},
      {id => $_, name => $user_groups{$_}} for @pgids;
    push @{$user_tmpl{current_group_ids}},
      {id => $_, name => $user_groups{$_}} for @cgids;
    $user_tmpl{size} = scalar keys %user_groups;

    # loop through User fields
    if ($q->param('errors')) {
        $user_tmpl{$_} = $q->param($_) for pkg('User')->USER_RW;
        $q->delete('errors');
    } else {
        $user_tmpl{$_} = $user->$_ for pkg('User')->USER_RW;
    }

    delete $user_tmpl{hidden};
    return \%user_tmpl;
}


# Update the user object with the values in the CGI query
sub update_user {
    my $self = shift;
    my $user = shift;
    my $q = $self->query();

    # overwrite object fields
    $user->$_($q->param($_) ? $q->param($_) : undef) 
      for grep { $_ ne 'hidden' } pkg('User')->USER_RW;

    # set password if we've been handed one
    my $pass = $q->param('password') || '';
    $user->password($pass) unless $pass eq '';

    # handle group ids
    my @gids = $q->param('current_group_ids');
    unless (@gids) {
        $user->group_ids_clear();
    } else {
        $user->group_ids(@gids);
    }

    # attempt to save
    eval {$user->save()};

    # Did we get a duplicate exception
    if ($@) {
        my %errors;
        if (ref $@ && $@->isa('Krang::User::Duplicate')) {
            my %dupes = %{$@->duplicates};
            for my $v(values %dupes) {
                for (@$v) {
                    my $error = "duplicate_" . $_;
                    $errors{$error} = 1;
                    $q->param('errors', 1);
                    add_message($error);
                }
            }
            return %errors;
        } elsif (ref $@ && $@->isa('Krang::User::InvalidGroup')) {
            my $ids = $@->group_id;
            my $error = (defined $ids && ref $ids) ? 'error_invalid_group_id' :
              'error_null_group';
            $errors{$error} = 1;
            $q->param('errors', 1);
            add_message($error);
            return %errors;
        } elsif (ref $@ && $@->isa('Krang::User::MissingGroup')) {
            my $error = "error_missing_group";
            $errors{$error} = 1;
            $q->param('errors', 1);
            add_message($error);
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
    my $q = $self->query();
    my %errors;

    # login, first, last, and email cannot be '' or just whitespace
    for (qw/login first_name last_name email/) {
        my $val = $q->param($_);

        unless ($_ eq 'email') {
            $errors{"error_invalid_$_"} = 1 if ($val eq '' || $val =~ /^\s+$/);

            # check login and pass length
            if ($_ eq 'login') {
                $errors{"error_login\_length"} = 1
                  unless (length($val) >= 6 ||
                          grep $val eq $_, pkg('User')->SHORT_NAMES);
            }
        } else {
            $errors{error_invalid_email} = 1
              if ($_ eq 'email' && $val ne ''
                  && $val !~ /[\w.-]+\@[\w.-]+\.\w+/);
        }

    }

    my ($mode, $pass, $cpass) = map {$q->param($_)}
      qw/rm new_password confirm_password/;

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

        $errors{error_password_length} = 1 if length $pass < 6;
    }

    # Add error messages
    add_message($_) for keys %errors;
    $q->param('errors', 1) if keys %errors;

    return %errors;
}



##############################
#####  PRIVATE METHODS   #####
##############################

# Handles rows for search run mode
sub search_row_handler {
    my ($row, $user) = @_;
    $row->{login} = $user->login();
    $row->{last} = $user->last_name();
    $row->{first} = $user->first_name();
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
