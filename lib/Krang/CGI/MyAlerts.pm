package Krang::CGI::MyAlerts;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => qw(CGI);
use strict;
use warnings;

use Carp qw(croak);
use Krang::ClassLoader 'Alert';
use Krang::ClassLoader 'User';
use Krang::ClassLoader Message      => qw(add_message add_alert);
use Krang::ClassLoader Session      => qw(%session);
use Krang::ClassLoader Widget       => qw(category_chooser);
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

    $self->run_modes(
        [
            qw(
              edit
              add
              delete_alerts
              )
        ]
    );

    $self->tmpl_path('MyAlerts/');
}

=over

=item edit

Displays current alerts edit form.

=cut

sub edit {
    my $self     = shift;
    my $error    = shift || '';
    my $q        = $self->query;
    my $user_id  = $ENV{REMOTE_USER};
    my $template = $self->load_tmpl('edit.tmpl', associate => $q, loop_context_vars => 1);
    $template->param($error => 1) if $error;

    my %alert_types = (
        new      => localize('New'),
        save     => localize('Save'),
        checkin  => localize('Check In'),
        checkout => localize('Check Out'),
        publish  => localize('Publish'),
        move     => localize('Move To'),
    );

    # get current alerts
    my @current_alerts = pkg('Alert')->find(user_id => $user_id);

    my @alert_loop;
    foreach my $alert (@current_alerts) {
        my $desk_name =
          $alert->desk_id ? localize((pkg('Desk')->find(desk_id => $alert->desk_id))[0]->name) : '';
        my $category =
          $alert->category_id
          ? (pkg('Category')->find(category_id => $alert->category_id))[0]->url
          : '';

        push(
            @alert_loop,
            {
                action      => $alert_types{$alert->action},
                alert_id    => $alert->alert_id,
                object_type => ucfirst(localize($alert->object_type)) || '',
                object_id   => $alert->object_id || '',
                desk        => ($alert->object_id && $alert->object_type eq 'media')
                ? localize('n/a')
                : $desk_name,
                category => $alert->object_id ? localize('n/a') : $category
            }
        );
    }

    $template->param(alert_loop => \@alert_loop);

    my @desks = pkg('Desk')->find;

    my %desk_labels;
    foreach my $d (@desks) {
        $desk_labels{$d->desk_id} = localize($d->name);
    }

    $template->param(
        object_type_selector => scalar $q->popup_menu(
            -name   => 'object_type',
            -values => ['', 'story', 'media'],
            -labels => {
                'story' => localize('Story'),
                'media' => localize('Media')
            }
        )
    );

    $template->param(
        object_id_selector => scalar $q->textfield(
            -name    => 'object_id',
            -default => '',
            -length  => 10
        )
    );

    $template->param(
        desk_selector => scalar $q->popup_menu(
            -name   => 'desk_id',
            -values => [
                '',
                sort { localize($desk_labels{$a}) cmp localize($desk_labels{$b}) } keys %desk_labels
            ],
            -labels => \%desk_labels
        )
    );

    $template->param(
        action_selector => scalar $q->popup_menu(
            -name   => 'action',
            -values => [sort keys %alert_types],
            -labels => \%alert_types
        )
    );

    my ($interface, $chooser) = category_chooser(
        name     => 'category_id',
        query    => $q,
        formname => "add_alert_form"
    );

    $template->param(
        category_chooser           => $chooser,
        category_chooser_interface => $interface
    );

    return $template->output;
}

=item add()

Commits new Krang::Alert to server.

=cut

sub add {
    my $self = shift;
    my $q    = $self->query();
    my %params;

    $params{user_id} = $ENV{REMOTE_USER};
    $params{action}  = $q->param('action');
    foreach ('object_type', 'object_id', 'category_id', 'desk_id') {
        $params{$_} = $q->param($_) || 'NULL';
    }

    # return error message on bad object type/ID
    my $object_type = $params{object_type};
    my $object_id   = $params{object_id};
    my $object_pkg  = ucfirst($object_type);
    add_alert("object_type_requires_id"), return $self->edit()
      if (($object_type eq 'NULL') != ($object_id eq 'NULL'));
    add_alert("no_object_with_that_id", type => $object_type, id => $object_id),
      return $self->edit()
      if ($object_id != 'NULL' && !pkg($object_pkg)->find($object_type . '_id' => $object_id));

    # return error message on bad desk combination
    add_alert("bad_desk_combo"), return $self->edit()
      if (($params{action} ne 'move') and ($params{desk_id} ne 'NULL'));
    add_alert("media_have_no_desks"), return $self->edit()
      if (($object_type eq 'media') and ($params{desk_id} ne 'NULL'));
    add_alert("move_needs_desk"), return $self->edit()
      if (($params{action} eq 'move') and ($params{desk_id} eq 'NULL'));
    add_alert("desk_requires_move"), return $self->edit()
      if (($params{action} ne 'move') and ($params{desk_id} ne 'NULL'));

    my @found = pkg('Alert')->find(%params);

    if (not @found) {
        foreach ('object_type', 'object_id', 'category_id', 'desk_id') {
            $params{$_} = undef if ($params{$_} eq 'NULL');
        }
        my $alert = pkg('Alert')->new(%params);
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
    my $self        = shift;
    my $q           = $self->query();
    my @delete_list = ($q->param('alert_delete_list'));

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

