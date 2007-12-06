package Krang::CGI::MyAlerts;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => qw(CGI);
use strict;
use warnings;

use Carp qw(croak);
use Krang::ClassLoader 'Alert';
use Krang::ClassLoader 'User';
use Krang::ClassLoader Message => qw(add_message add_alert);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Widget => qw(category_chooser);
use Krang::ClassLoader Localization => qw(localize);

=head1 NAME

Krang::CGI::MyAlerts - interface to edit Krang user alerts.

=head1 SYNOPSIS

  use Krang::ClassLoader 'CGI::MyAlerts';
  my $app = pkg('CGI::MyAlerts')->new();
  $app->run();

=head1 DESCRIPTION

Krang::CGI::MyAlerts provides a form in which a krang user
can view and change thier alerts.  

=head1 INTERFACE

Following are descriptions of all the run-modes provided by
Krang::CGI::MyAlerts.

=cut

# setup runmodes
sub setup {
    my $self = shift;

    $self->start_mode('edit');

    $self->run_modes([qw(
                            edit
                            add
                            delete_alerts
                    )]);

    $self->tmpl_path('MyAlerts/');
}

=over

=item edit

Displays current alerts edit form.

=cut

sub edit {
    my $self = shift;
    my $error = shift || '';
    my $q = $self->query;
    my $user_id = $ENV{REMOTE_USER};
    my $template = $self->load_tmpl('edit.tmpl', associate => $q, loop_context_vars => 1);
    $template->param( $error => 1 ) if $error;

    my %alert_types = ( new      => localize('New'      ),
                        save     => localize('Save'     ),
                        checkin  => localize('Check In' ),
                        checkout => localize('Check Out'),
                        publish  => localize('Publish'  ),
                        move     => localize('Move To'  ),
		      );

    # get current alerts
    my @current_alerts = pkg('Alert')->find( user_id => $user_id );

    my @alert_loop;
    foreach my $alert (@current_alerts) {
        my $desk = $alert->desk_id ? (pkg('Desk')->find( desk_id => $alert->desk_id))[0]->name : '';
        my $category = $alert->category_id ? (pkg('Category')->find( category_id => $alert->category_id))[0]->url : '';

        push (@alert_loop, {        action => $alert_types{$alert->action},
                                    alert_id => $alert->alert_id,
                                    desk => $desk,
                                    category => $category } );
    }

    $template->param( alert_loop => \@alert_loop );

    my @desks = pkg('Desk')->find;

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

    my ($interface, $chooser) = category_chooser(name     => 'category_id',
                                                 query    => $q,
                                                 formname => "add_alert_form");

    $template->param(category_chooser            => $chooser,
                     category_chooser_interface  => $interface);

    return $template->output;
}

=item add()

Commits new Krang::Alert to server.

=cut

sub add {
    my $self = shift;
    my $q = $self->query();
    my %params;
                                                                                
    $params{user_id} = $ENV{REMOTE_USER};
    $params{action} = $q->param('action_list');
    $params{desk_id} = $q->param('desk_list') ? $q->param('desk_list') : 'NULL';    $params{category_id} = $q->param('category_id') ? $q->param('category_id') : 'NULL';
                                                                                
    # return error message on bad combination
    add_alert("bad_desk_combo"), return $self->edit() if ( ($params{action} ne 'move') and ($params{desk_id} ne 'NULL') );
    add_alert("move_needs_desk"),  return $self->edit() if ( ($params{action}
eq 'move') and ($params{desk_id} eq 'NULL') );
    add_alert("desk_requires_move"),  return $self->edit() if ( ($params{action} ne 'move') and ($params{desk_id} ne 'NULL') );
                                                                                
    my @found = pkg('Alert')->find( %params );
                                                                                
    if (not @found) {
        $params{category_id} = undef if ($params{category_id} eq 'NULL');
        $params{desk_id} = undef if ($params{desk_id} eq 'NULL');
                                                                                
        my $alert = pkg('Alert')->new( %params );
        $alert->save();
        add_message("alert_added");
    } else {
        add_alert("duplicate_alert");
    }
                                                                                
    return $self->edit();
}

=item delete_alerts()
                                                                                
Deletes selected alerts.
                                                                                
=cut
                                                                                
sub delete_alerts {
    my $self = shift;
    my $q = $self->query();
    my @delete_list = ( $q->param('alert_delete_list') );
                                                                                
    unless (@delete_list) {
        add_alert('missing_alert_delete_list');
        return $self->edit();
    }
                                                                                
    foreach my $alert_id (@delete_list) {
        pkg('Alert')->delete($alert_id);
    }
                                                                                
    add_message('deleted_selected');
    return $self->edit();
                                                                                
}
                                                                                
=back
                                                                                
=cut
                                                                                
1;

