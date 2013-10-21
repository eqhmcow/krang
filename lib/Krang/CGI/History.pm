package Krang::CGI::History;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => qw(CGI);
use strict;
use warnings;

our %ACTION_LABELS = (
    new      => 'created',
    save     => 'saved',
    checkin  => 'checked in',
    checkout => 'checked out',
    steal    => 'stolen',
    publish  => 'published',
    deploy   => 'deployed',
    move     => 'moved',
    revert   => 'reverted',
    retire   => 'retired',
    unretire => 'unretired',
    trash    => 'trashed',
    untrash  => 'untrashed',
    resize   => 'resized',
    crop     => 'cropped',
    rotate   => 'rotated',
    flip     => 'flipped',
);

use Carp qw(croak);
use Krang::ClassLoader 'History';
use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader 'Desk';
use Krang::ClassLoader Localization => qw(localize);

=head1 NAME

Krang::CGI::History - web interface to view history logs


=head1 SYNOPSIS

  use Krang::ClassLoader 'CGI::History';
  my $app = pkg('CGI::History')->new();
  $app->run();

=head1 DESCRIPTION

Krang::CGI::History provides the log screen in Krang which displays
the history entries associated with a given object.

=head1 INTERFACE

Following are descriptions of all the run-modes provided by
Krang::CGI::History.  The default (and sole) run-mode for
Krang::CGI::History is 'show'.

=head2 Run-Modes

=over 4

=cut

# setup runmodes
sub setup {
    my $self = shift;

    $self->start_mode('show');

    $self->run_modes(
        [
            qw(
              show
              )
        ]
    );

    $self->tmpl_path('History/');
}

=item show

Display the log data associate with an object.  Three types of objects
have history - templates, media and stories.  The following parameters
are used by this run-mode:

=over 4

=item story_id

=item media_id

=item template_id

One of these (and only one) must be set to the ID of the object in
question.

=item history_return_script

This must name the script to return to when the user clicks the return
button.  For example, when calling history.pl from story.pl I would
include:

  <input name=history_return_script value=story.pl type=hidden>

=item history_return_params

This must be set to a list of key-value pairs which will be submitted
back to the script specified by history_return_script.  For example,
to return to story edit mode after viewing the log these parameters
might be used:

  <input name=history_return_params value=rm   type=hidden>
  <input name=history_return_params value=edit type=hidden>

=back

=cut

sub show {
    my $self     = shift;
    my $query    = $self->query;
    my $template = $self->load_tmpl('show.tmpl', associate => $query, loop_context_vars => 1);

    # load params
    my $id      = $query->param('id')      or croak("Missing required id");
    my $class   = $query->param('class')   or croak("Missing required class param");
    my $id_meth = $query->param('id_meth');
    my $history_return_script = $query->param('history_return_script')
      or croak("Missing required history_return_script");
    my @history_return_params = $query->param('history_return_params')
      or croak("Missing required history_return_params");
    my $label = $query->param('label') || (split('::', $class))[-1];    # from the query or class
    $self->param(label => $label);                                      # save for our row_handler

    # we assume the class needs to run through pkg(); if it doesn't work, just use the class name
    my $real_class = pkg($class);
    eval "require $real_class";
    if ($@) {
        $real_class = $class;
        eval "require $real_class";
        croak("Unable to load class $real_class: $@") if $@;
    }

    $id_meth ||= $real_class->id_meth;

    # load an object
    my ($object) = $real_class->find($id_meth => $id);
    croak("Unable to load object!") unless $object;

    # setup return variables
    my $return_hidden = "";
    for (my $x = 0 ; $x <= $#history_return_params ; $x += 2) {
        my ($name, $value) = @history_return_params[($x, $x + 1)];
        $return_hidden .= $query->hidden(
            -name     => $name,
            -default  => $value,
            -override => 1
        ) . "\n";
    }
    $template->param(
        return_script => $history_return_script,
        return_hidden => $return_hidden,
        label         => localize($label . ' Log'),
    );
    if ($template->query(name => 'id_meth')) {
        $template->param(id_meth => $id_meth);
    }

    # setup the pager
    my $pager = pkg('HTMLPager')->new(
        cgi_query    => $query,
        persist_vars => {
            rm                    => 'show',
            id                    => $id,
            class                 => $class,
            id_meth               => $id_meth,
            label                 => $label,
            history_return_script => $history_return_script,
            history_return_params => \@history_return_params,
        },
        use_module    => pkg('History'),
        find_params   => {object => $object},
        columns       => [qw(action user timestamp attr)],
        column_labels => {
            action    => 'Action',
            user      => 'Triggered By',
            timestamp => 'Date',
            attr      => 'Attributes',
        },
        columns_sortable        => [qw( timestamp action )],
        default_sort_order_desc => 1,
        command_column_commands => [],
        command_column_labels   => {},
        row_handler             => sub { $self->show_row_handler(@_) },
        id_handler              => sub { 0 },
    );

    # Set up output
    $pager->fill_template($template);

    return $template->output;
}

sub show_row_handler {
    my $self  = shift;
    my $q     = $self->query;
    my $label = $self->param('label');
    my ($row, $history, $pager) = @_;

    # setup action
    my $object_label = $self->object_label($history);
    $row->{action} =
      $q->escapeHTML("$object_label " . localize($self->action_label($history->action)));
    $row->{action} .=
      ' (' . localize("from schedule") . ')'
      if $history->schedule_id;

    # setup user
    my ($user) = pkg('User')->find(user_id => $history->user_id);
    if ($user) {
        $row->{user} = $q->escapeHTML($user->first_name . " " . $user->last_name);
    } else {

        # user does not exist, might have been deleted
        $row->{user} = localize("Unknown User");
    }

    # setup date
    $row->{timestamp} = $history->timestamp->strftime(localize('%m/%d/%Y %I:%M %p'));

    # some events have attributes
    my $attr = "";
    $attr .= localize("Version:") . ' ' . $history->version
      if $history->version;
    $attr .=
      localize("Desk:") . ' ' . localize((pkg('Desk')->find(desk_id => $history->desk_id))[0]->name)
      if $history->desk_id;
    $attr .= localize("from") . ' ' . $history->origin
      if $history->origin;
    $row->{attr} = $q->escapeHTML($attr);
}

sub object_label {
    my ($self, $history) = @_;
    return ucfirst((split('::', $history->object_type))[-1]);
}

sub action_label {
    my ($self, $action) = @_;
    return $ACTION_LABELS{$action} || $action;
}

=back

=cut

1;
