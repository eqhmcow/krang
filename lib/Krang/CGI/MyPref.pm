package Krang::CGI::MyPref;
use base qw(Krang::CGI);
use strict;
use warnings;

use Carp qw(croak);
use Krang::MyPref;
use Krang::Alert;
use Krang::User;
use Krang::Message qw(add_message);
use Krang::Session qw(%session);
use Krang::Widget qw(category_chooser);

=head1 NAME

Krang::CGI::MyPref - interface to edit Krang user preferences,
alerts and password.

=head1 SYNOPSIS
  
  use Krang::CGI::Pref;
  my $app = Krang::CGI::MyPref->new();
  $app->run();

=head1 DESCRIPTION

Krang::CGI::MyPref provides a form in which a krang user
can view and change thier preferences and alerts.  See Krang::MyPref
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
                            add_alert
                            delete_alerts
                            update_prefs
                    )]);

    $self->tmpl_path('MyPref/');    
}

=over 

=item edit

Displays current preferences/alerts edit form.

=cut

sub edit {
    my $self = shift;
    my $error = shift || '';
    my $q = $self->query;
    my $user_id = $session{user_id};
    my $template = $self->load_tmpl('edit.tmpl', associate => $q);
    $template->param( $error => 1 ) if $error;
    
    my %alert_types = ( new => 'New', 
                        save => 'Save',
                        checkin => 'Check In',
                        checkout => 'Check Out',
                        publish => 'Publish',
                        move => 'Move To' );    
    
    my $set_sps = Krang::MyPref->get('search_page_size') || '';

    $template->param(search_page_size => $set_sps);
    $template->param(search_results_selector => scalar
                      $q->popup_menu(-name    => 'search_results_page',
                                         -values  => ['', 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95 ],
                                         -default => $set_sps));

    # get current alerts
    my @current_alerts = Krang::Alert->find( user_id => $user_id );

    my @alert_loop;
    foreach my $alert (@current_alerts) {
        my $desk = $alert->desk_id ? (Krang::Desk->find( desk_id => $alert->desk_id))[0]->name : '';
        my $category = $alert->category_id ? (Krang::Category->find( category_id => $alert->category_id))[0]->url : '';

        push (@alert_loop, {        action => $alert_types{$alert->action}, 
                                    alert_id => $alert->alert_id,
                                    desk => $desk,
                                    category => $category } );
    }

    $template->param( alert_loop => \@alert_loop );

    my @desks = Krang::Desk->find;

    my %desk_labels;
    foreach my $d (@desks) {
        $desk_labels{$d->desk_id} = $d->name;
    }
    
    $template->param(desk_selector => scalar 
                    $q->popup_menu( -name    => 'desk_list', 
                                    -values  => ['',keys %desk_labels],
                                    -labels  => \%desk_labels ) );

    $template->param(action_selector => scalar
                    $q->popup_menu( -name    => 'action_list',
                                    -values  => [sort keys %alert_types],
                                    -labels  => \%alert_types ) );
     
    $template->param( category_chooser => category_chooser(name => 'category_id', query => $q, formname => "add_alert_form") );
 
    return $template->output; 
}

=item add_alert() 

Commits new Krang::Alert to server.

=cut

sub add_alert {
    my $self = shift;
    my $q = $self->query();
    my %params;
    
    $params{user_id} = $session{user_id};
    $params{action} = $q->param('action_list');
    $params{desk_id} = $q->param('desk_list') if $q->param('desk_list');
    $params{category_id} = $q->param('category_id') if $q->param('category_id'); 
  
    # return error message on bad combination
    add_message("bad_desk_combo"), return $self->edit() if ( ($params{action} ne 'move') and ($params{desk_id}) );
    add_message("move_needs_desk"),  return $self->edit() if ( ($params{action} eq 'move') and (not $params{desk_id}) );
 
    my $alert = Krang::Alert->new( %params );
    $alert->save();
    add_message("alert_added");
 
    return $self->edit();
}

=item update_prefs()

Updates preferences and user password

=cut

sub update_prefs {
    my $self = shift;
    my $q = $self->query();

    # update search_page_size
    Krang::MyPref->set(search_page_size => $q->param('search_results_page')), add_message("changed_search_page_size") if ($q->param('search_page_size') ne $q->param('search_results_page'));
    
    if ($q->param('new_password')) {
        my $user_id = $session{user_id};
        my $user = (Krang::User->find( user_id => $user_id ))[0];
        $user->password($q->param('new_password'));
        $user->save;
        add_message("changed_password");
    }
 
    return $self->edit();
}

=item update_alerts()

Deletes selected alerts.

=cut

sub delete_alerts {
    my $self = shift;
    my $q = $self->query();
    my @delete_list = ( $q->param('alert_delete_list') );
    
    unless (@delete_list) {
        add_message('missing_alert_delete_list');
        return $self->edit();
    }
    
    foreach my $alert_id (@delete_list) {
        Krang::Alert->delete($alert_id);
    }
    
    add_message('deleted_selected');
    return $self->edit();

}

=back

=cut

1;
