package Krang::CGI::Desk;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::CGI::Desk - displays stories on a particular desk

=head1 SYNOPSIS

  use Krang::ClassLoader 'CGI::Desk';
  my $app = pkg('CGI::Desk')->new();
  $app->run();

=head1 DESCRIPTION

This application manages display of stories on desks for Krang.

=head1 INTERFACE

=head2 Run-Modes

=over 4

=cut

use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader Widget  => qw(format_url);
use Krang::ClassLoader Message => qw(add_message add_alert);
use Krang::ClassLoader 'Desk';
use Krang::ClassLoader 'Group';
use Krang::ClassLoader 'Localization' => qw(localize);
use Krang::ClassLoader 'CGI::Story';

use Krang::ClassLoader base => 'CGI';

sub setup {
    my $self = shift;
    $self->start_mode('show');
    $self->mode_param('rm');
    $self->tmpl_path('Desk/');
    $self->run_modes(
        [
            qw(
              show
              checkout_checked
              goto_edit
              goto_log
              goto_view
              move
              move_checked
              )
        ]
    );

}

=item show

Shows the paging desk view.  This is the default runmode and it
requires no parameters.

=cut

sub show {
    my $self     = shift;
    my $query    = $self->query;
    my $template = $self->load_tmpl(
        "desk.tmpl",
        associate         => $query,
        die_on_bad_params => 0,
        loop_context_vars => 1,
        global_vars       => 1
    );

    my $desk_id = $query->param('desk_id');

    # make sure they have permissions to view this desk
    my %perms = pkg('Group')->user_desk_permissions();
    unless ($perms{$desk_id} && $perms{$desk_id} ne 'hide') {
        return $self->access_forbidden;
    }

    # set up the desk selector
    my ($desk) = pkg('Desk')->find(desk_id => $desk_id);
    $template->param(desk_name => localize($desk->name));
    $template->param(desk_id   => $desk_id);

    my @found_desks = pkg('Desk')->find();
    my @desk_loop   = ();

    if (pkg('Group')->may_move_story_from_desk($desk_id)) {
        foreach my $found_desk (@found_desks) {
            my $found_desk_id = $found_desk->desk_id;

            next unless pkg('Group')->may_move_story_to_desk($found_desk_id);
            next if $found_desk_id eq $desk_id;

            my $is_selected = ($found_desk->order eq ($desk->order + 1)) ? 1 : 0;
            push @desk_loop,
              {
                choice_desk_id   => $found_desk_id,
                choice_desk_name => localize($found_desk->name),
                is_selected      => $is_selected
              };
        }
        $template->param(may_move  => 1);
        $template->param(desk_loop => \@desk_loop);
    }

    # permissions
    my %admin_perms = pkg('Group')->user_admin_permissions();
    $template->param(may_publish => $admin_perms{may_publish});

    # localize labels
    my $labels = {
        story_id   => localize('ID'),
        title      => localize('Title'),
        url        => localize('URL'),
        cover_date => localize('Cover Date'),
    };

    # setup sort selector
    my $sort = $query->param('krang_pager_sort_field') || 'story_id';
    $template->param(
        'sort_select' => scalar $query->popup_menu(
            -name     => 'sort_select',
            -values   => ['story_id', 'title', 'url', 'cover_date'],
            -labels   => $labels,
            -default  => $sort,
            -override => 1,
            -onchange => "Krang.Pager.sort(this.options[this.selectedIndex].value,0)",
        )
    );

    # setup paging list of objects
    my $pager = pkg('HTMLPager')->new(
        cgi_query  => $query,
        use_module => pkg('Story'),
        columns =>
          ['id', 'version', 'url', 'title', 'story_type', 'command_column', 'checkbox_column'],
        columns_sortable => [],
        find_params      => {desk_id => $desk_id, may_see => 1, checked_out => 0},
        command_column_commands => ['view', 'log', 'edit'],
        command_column_labels   => {
            view => 'View Detail',
            log  => 'View Log',
            edit => 'Edit'
        },
        id_handler  => sub { $self->_obj2id(@_) },
        row_handler => sub { $self->_row_handler(@_, \@desk_loop) },
    );

    # Run the pager
    $pager->fill_template($template);

    return $template->output;
}

sub _row_handler {
    my ($self, $row, $obj, $pager, $desk_loop) = @_;
    $row->{desk_loop}  = $desk_loop;
    $row->{story_id}   = $obj->story_id;
    $row->{title}      = $obj->title;
    $row->{story_type} = localize($obj->class->display_name);
    $row->{url}        = format_url(
        url    => $obj->url,
        class  => 'story-preview-link',
        name   => 'story_' . $row->{story_id},
        length => 50
    );
    $row->{may_edit} = $obj->may_edit;

    # setup version
    $row->{version} = $obj->version;

    # cover_date
    my $tp = $obj->cover_date;
    $row->{cover_date} =
      (ref($tp)) ? $tp->strftime(localize('%m/%d/%Y %I:%M %p')) : localize('[n/a]');

    # reformat command_column to be in a list
    my $cc = $row->{command_column};
    if ($cc) {
        $cc =~ s|>(\s+)?<input|></li> <li><input|g;
        $cc = '<li>' . $cc . '</li>';
        $row->{command_column} = $cc;
    }

}

=item checkout_checked

Checks out a list of checked objects.  

=cut

sub checkout_checked {
    my $self                  = shift;
    my $query                 = $self->query;
    my $something_checked_out = 0;
    foreach my $obj (map { $self->_id2obj($_) } $query->param('krang_pager_rows_checked')) {
        eval { $obj->checkout };
        if (my $e = $@) {
            if (ref $e && $e->isa('Krang::Story::CheckedOut')) {
                my ($thief) = pkg('User')->find(user_id => $e->user_id);
                add_alert(
                    'story_stolen_before_checkout',
                    id    => $obj->story_id,
                    thief => CGI->escapeHTML($thief->display_name),
                );
            } else {
                die $e;    # just rethrow
            }
        } else {
            $something_checked_out = 1;
        }
    }

    if ($something_checked_out) {
        add_message('checkout_checked');
        $self->header_props(-uri => 'workspace.pl');
        $self->header_type('redirect');
        return "Redirecting to workspace.pl";
    } else {
        return $self->show;
    }
}

=item move

Moves story to selected desk,

=cut 

sub move {
    my $self  = shift;
    my $query = $self->query;
    my $obj   = $self->_id2obj($query->param('id'));

    # check if they may *move* object
    return $self->access_forbidden()
      unless pkg('Group')->may_move_story_from_desk($obj->desk_id);

    # check if they may move object to desired desk
    my $desk_id = $self->query->param('move_' . $obj->story_id);
    return $self->access_forbidden()
      unless pkg('Group')->may_move_story_to_desk($desk_id);

    $self->_do_move($obj, $desk_id);
    return $self->show;
}

=item move_checked

Moves list of checked stories to desks.

=cut

sub move_checked {
    my $self    = shift;
    my $query   = $self->query;
    my $desk_id = $self->query->param('move_to_desk_id');
    foreach my $obj (map { $self->_id2obj($_) } $query->param('krang_pager_rows_checked')) {

        # check if they may *move* object
        return $self->access_forbidden()
          unless pkg('Group')->may_move_story_from_desk($obj->desk_id);

        # check if they may move object to desired desk
        return $self->access_forbidden()
          unless pkg('Group')->may_move_story_to_desk($desk_id);

        $self->_do_move($obj, $desk_id);
    }
    return $self->show;
}

=item goto_edit

Redirects to the story edit screen 

=cut

sub goto_edit {
    my $self  = shift;
    my $query = $self->query;
    my $obj   = $self->_id2obj($query->param('id'));
    Krang::CGI::Story->_cancel_edit_goes_to('desk.pl?desk_id=' . $obj->desk_id);

    eval { $obj->checkout };
    if (my $e = $@) {
        if (ref $e && $e->isa('Krang::Story::CheckedOut')) {
            add_alert('story_stolen_before_checkout', id => $obj->story_id, thief => $e->user_id);
        } else {
            die $e;    # just rethrow
        }
        return $self->show;
    } else {
        $self->header_props(-uri => 'story.pl?rm=edit&story_id=' . $obj->story_id);
        $self->header_type('redirect');
        return "Redirecting to edit story";
    }
}

=item goto_log

Redirects to the story history view

=cut

sub goto_log {
    my $self    = shift;
    my $query   = $self->query;
    my $obj     = $self->_id2obj($query->param('id'));
    my $desk_id = $query->param('desk_id');

    # redirect as appropriate
    my $id_meth = $obj->id_meth;
    my $id      = $obj->$id_meth;

    my $uri =
        "history.pl?id=$id&history_return_script=desk.pl&history_return_params=rm"
      . "&history_return_params=show&history_return_params=desk_id"
      . "&history_return_params=$desk_id&class=Story&id_meth=$id_meth";

    # mix in pager params for return
    foreach my $name (grep { /^krang_pager/ } $query->param) {
        $uri .= "&history_return_params=${name}&history_return_params=" . $query->param($name);
    }

    $self->header_props(-uri => $uri);
    $self->header_type('redirect');
    return "";
}

=item goto_view

Redirects to the story element view

=cut

sub goto_view {
    my $self    = shift;
    my $query   = $self->query;
    my $obj     = $self->_id2obj($query->param('id'));
    my $desk_id = $query->param('desk_id');

    $self->header_props(-uri =>
          "story.pl?return_script=desk.pl&return_params=rm&return_params=show&return_params=desk_id&return_params=$desk_id&rm=view&story_id="
          . $obj->story_id);

    $self->header_type('redirect');
    return "";

}

#
# Utility functions
#

sub _obj2id {
    my ($self, $obj) = @_;
    return $obj->story_id;
}

# transform story_id into an object
sub _id2obj {
    my ($self, $id) = @_;
    my $obj;
    ($obj) = pkg('Story')->find(story_id => $id);
    croak("Unable to load story $id")
      unless $obj;
    return $obj;
}

# move one story to another desk
sub _do_move {
    my ($self, $obj, $desk_id) = @_;

    my $story_id = $obj->story_id;
    my ($desk) = pkg('Desk')->find(desk_id => $desk_id);
    my $desk_name = $desk ? localize($desk->name) : '';

    eval { $obj->move_to_desk($desk_id); };

    if ($@ and ref($@)) {
        if ($@->isa('Krang::Story::CheckedOut')) {
            add_alert(
                'story_cant_move_checked_out',
                id   => $story_id,
                desk => $desk_name
            );
        } elsif ($@->isa('Krang::Story::NoDesk')) {
            add_alert(
                'story_cant_move_no_desk',
                story_id => $story_id,
                desk_id  => $desk_id
            );
        }
    } else {
        add_message("moved_story", id => $story_id, desk => $desk_name);
    }
}

1;

=back

=cut
