package Krang::CGI::MyPref;
use base qw(Krang::CGI);
use strict;
use warnings;

use Carp qw(croak);
use Krang::MyPref;
use Krang::User;
use Krang::Message qw(add_message);
use Krang::Session qw(%session);

=head1 NAME

Krang::CGI::MyPref - interface to edit Krang user preferences
 and password.

=head1 SYNOPSIS
  
  use Krang::CGI::MyPref;
  my $app = Krang::CGI::MyPref->new();
  $app->run();

=head1 DESCRIPTION

Krang::CGI::MyPref provides a form in which a krang user
can view and change thier preferences.  See Krang::MyPref
for which prefs are available.

=head1 INTERFACE

Following are descriptions of all the run-modes provided by
Krang::CGI::MyPref.

=cut

# setup runmodes
sub setup {
    my $self = shift;

    $self->start_mode('edit');
    
    $self->run_modes([qw(
                            edit
                            update_prefs
                    )]);

    $self->tmpl_path('MyPref/');    
}

=over 

=item edit

Displays current preferences edit form.

=cut

sub edit {
    my $self = shift;
    my $error = shift || '';
    my $q = $self->query;
    my $user_id = $ENV{REMOTE_USER};
    my $template = $self->load_tmpl('edit.tmpl', associate => $q);
    $template->param( $error => 1 ) if $error;
    
    my $set_sps = Krang::MyPref->get('search_page_size');

    $template->param(search_results_selector => scalar
                      $q->popup_menu(-name    => 'search_results_page',
                                         -values  => [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95 ],
                                         -default => $set_sps));

    return $template->output; 
}

=item update_prefs()

Updates preferences and user password

=cut

sub update_prefs {
    my $self = shift;
    my $q = $self->query();

    # update search_page_size
    Krang::MyPref->set(search_page_size => $q->param('search_results_page')), add_message("changed_search_page_size");
    
    if ($q->param('new_password')) {
        my $user_id = $ENV{REMOTE_USER};
        my $user = (Krang::User->find( user_id => $user_id ))[0];
        $user->password($q->param('new_password'));
        $user->save;
        add_message("changed_password");
    }
 
    return $self->edit();
}

=back

=cut

1;
