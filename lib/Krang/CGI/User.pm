package Krang::CGI::User;

=head1 NAME

Krang::CGI::User - 
Abstract of web application....


=head1 SYNOPSIS

  use Krang::CGI::User;
  my $app = Krang::CGI::User->new();
  $app->run();


=head1 DESCRIPTION

Overview of functionality and purpose of 
web application module Krang::CGI::User...

=cut


use strict;
use warnings;


use base qw/Krang::CGI/;


use Krang::History;
use Krang::HTMLPager;
use Krang::Log;
use Krang::Message qw(add_message);
use Krang::Pref;
use Krang::Session qw(%session);
use Krang::User;


# alias user_groups hash, for convenience :)
my %user_groups = %Krang::User::user_groups;

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


sub teardown {
	my $self = shift;
}



##############################
#####  RUN-MODE METHODS  #####
##############################

=head1 INTERFACE



=head1 RUN MODES

=over 4


=item * add

Description of run-mode add...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub add {
	my $self = shift;

	my $q = $self->query();

	return $self->dump_html();
}


=item * cancel_add

Description of run-mode cancel_add...

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


=item * save_add

Description of run-mode save_add...

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


=item * save_stay_add

Description of run-mode save_stay_add...

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


=item * delete

Deletes the user from 'edit' screen and redirects to 'search' run mode.

It expects a 'user_id' query param.

=cut

sub delete {
	my $self = shift;

	my $q = $self->query();
        my $user_id = $q->param('user_id');

	return $self->dump_html();
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
        Krang::User->delete($_) for @user_delete_list;

        add_message('message_selected_deleted');

	return $self->search();
}


=item * edit

Display a screen allowing the end-user to edit the User object selected from
the 'search' screen.

This run mode expects a 'user_id' query param and it will croak if it's missing
or invalid.

=cut

sub edit {
	my $self = shift;
        my %ui_messages = @_;
	my $q = $self->query();
        my $user_id = $q->param('user_id');
        my ($user) = Krang::User->find(user_id => $user_id);

        croak(__PACKAGE__ . "->edit(): No Krang::User object found matching " .
              "user_id '$user_id'")
          unless defined $user;

        # Store in session, just following Jesse's lead
        $session{EDIT_USER} = $user;

        my $t = $self->load_tmpl("edit_view.tmpl",
                                 associate => $q);

        $t->param(%ui_messages) if %ui_messages;

        # make group_ids checkbox
        my $default = $user->group_ids;
        my @values = keys %user_groups;
        my $size = scalar @values;
        my $group_ids = $q->scrolling_list(-name => 'group_ids',
                                           -values => \@values,
                                           -default => $default,
                                           -size => $size,
                                           -multiple => 'true',
                                           -labels => \%user_groups,);
        $t->param(group_ids => $group_ids);

        # loop through User fields
        for (Krang::User::USER_RO, Krang::User::USER_RW) {
            no strict;
            $t->param($_ => $user->$_);
        }

        return $t->output();
}


=item * cancel_edit

Description of run-mode cancel_edit...

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


=item * save_edit

Description of run-mode save_edit...

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


=item * save_stay_edit

Description of run-mode save_stay_edit...

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


=item * search

Display a list of all users or those matching the supplied search criteria.


Description of run-mode search...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

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
        my $pager = Krang::HTMLPager->new(cgi_query => $q,
                                          persist_vars => {
                                                           rm => 'search',
                                                           search_filter =>
                                                           $search_filter,
                                                          },
                                          use_module => 'Krang::User',
                                          find_params =>
                                          {simple_search => $search_filter},
                                          columns => [
                                                      'login',
                                                      'last',
                                                      'first',
                                                      'email',
                                                      'phone',
                                                      'groups',
                                                      'command_column',
                                                      'checkbox_column',
                                                     ],
                                          column_labels => {
                                                            login => 'Login',
                                                            last =>
                                                            'Last Name',
                                                            first =>
                                                            'First Name',
                                                            email => 'Email',
                                                            phone => 'Phone #',
                                                            groups =>
                                                            'User Groups',
                                                           },
                                          columns_sortable =>
                                          [qw(login last first email)],
                                          columns_sort_map => {
                                                               last =>
                                                               'last_name',
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




##############################
#####  PRIVATE METHODS   #####
##############################

# Handles rows for search run mode
sub search_row_handler {
    my ($row, $user) = @_;
    $row->{login} = $user->login();
    $row->{last} = $user->last_name();
    $row->{first} = $user->first_name();
    $row->{email} = $user->email();
    $row->{phone} = $user->phone();
    $row->{groups} = join(", ", map {$Krang::User::user_groups{$_}}
                          $user->group_ids());
}


=back

=head1 AUTHOR

Author of Module <author@module>


=head1 SEE ALSO

L<Krang::History>, L<Krang::HTMLPager>, L<Krang::Log>, L<Krang::Message>, L<Krang::Pref>, L<Krang::Session>, L<Krang::User>, L<Krang::CGI>

=cut



my $quip = <<END;
I do not feel obliged to believe that the same God who has endowed us
with sense, reason, and intellect has intended us to forgo their use.

-- Galileo Galilei
END
