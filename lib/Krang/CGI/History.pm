package Krang::CGI::History;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => qw(CGI);
use strict;
use warnings;

# readable labels for Krang::History actions
our %ACTION_LABELS = (
                      new      => 'Created',
                      save     => 'Saved',
                      checkin  => 'Checked In',
                      checkout => 'Checked Out',
                      publish  => 'Published',
                      deploy   => 'Deployed',
                      move     => 'Moved',
                      revert   => 'Reverted',
                     );

use Carp qw(croak);
use Krang::ClassLoader 'History';
use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader 'Desk';

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

    $self->run_modes([qw(
                         show
                        )]);

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
    my $self = shift;
    my $query = $self->query;
    my $template = $self->load_tmpl('show.tmpl', associate => $query);

    # load params
    my $story_id    = $query->param('story_id');
    my $media_id    = $query->param('media_id');
    my $template_id = $query->param('template_id');
    croak("Missing required story_id, media_id or template_id")
      if not $story_id and not $media_id and not $template_id;
    my $history_return_script = $query->param('history_return_script');
    croak("Missing required history_return_script")
      unless $history_return_script;
    my @history_return_params = $query->param('history_return_params');
    croak("Missing required history_return_params")
      unless @history_return_params;
    

    # load an object
    my $object;
    if ($story_id) {
        ($object) = pkg('Story')->find(   story_id    => $story_id);
    } elsif ($media_id) {
        ($object) = pkg('Media')->find(   media_id    => $media_id);
    } else {
        ($object) = pkg('Template')->find(template_id => $template_id);
    }
    croak("Unable to load object!")
      unless $object;

    # setup return variables
    $template->param(return_script => $history_return_script);
    my $return_hidden = "";
    for(my $x = 0; $x <= $#history_return_params; $x += 2) {
        my ($name, $value) = @history_return_params[($x, $x+1)];
        $return_hidden .= $query->hidden(-name    => $name,
                                         -default => $value,
                                         -override => 1) . "\n";
    }
    $template->param(return_hidden => $return_hidden);


    # setup the pager
    my $pager = pkg('HTMLPager')->new
      (
       cgi_query => $query,
       persist_vars => {
                        story_id => $story_id,
                        media_id => $media_id,
                        template_id => $template_id,
                        history_return_script => $history_return_script,
                        history_return_params => \@history_return_params,
                       },
       use_module => pkg('History'),
       find_params => { object => $object },
       columns => [qw(action user timestamp attr)],
       column_labels => {
                         action    => 'Action',
                         user      => 'Triggered By',
                         timestamp => 'Timestamp',
                         attr      => 'Attributes',
                        },
       columns_sortable => [qw( timestamp action )],
       default_sort_order_desc => 1,
       command_column_commands => [],
       command_column_labels   => {},
       row_handler => sub { $self->show_row_handler(@_) },
       id_handler  => sub { 0 },
      );

    # Set up output
    $template->param(pager_html => $pager->output());
    # $template->param(row_count => $pager->row_count());

    return $template->output;

}

sub show_row_handler {
    my $self = shift;
    my $q    = $self->query;
    my ($row, $history) = @_;
    
    # setup action
    my $name = ucfirst((split('::', $history->object_type))[1]);
    my $action = $history->action;
    $action = $ACTION_LABELS{$action} if exists $ACTION_LABELS{$action};
    $row->{action} = $q->escapeHTML("$name $action");
    
    # setup user
    my ($user) = pkg('User')->find(user_id => $history->user_id);
    if ($user) {
        $row->{user} = $q->escapeHTML($user->first_name . " " . $user->last_name);
    } else {
        # user does not exist, might have been deleted
        $row->{user} = "Unknown User";
    }

    # setup date
    $row->{timestamp}   = $history->timestamp->strftime('%b %e, %Y %l:%M %p'); 

    # some events have attributes
    my $attr = "";
    $attr .= "Version: " . $history->version
      if $history->version;
    $attr .= "Desk: " . (pkg('Desk')->find( desk_id => $history->desk_id))[0]->name if $history->desk_id;
    $row->{attr} = $attr;
}


=back

=cut

1;
