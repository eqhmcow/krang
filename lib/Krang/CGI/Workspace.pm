package Krang::CGI::Workspace;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::CGI::Workspace - the my workspace application

=head1 SYNOPSIS

None.

=head1 DESCRIPTION

This application manages the My Workspace for Krang.

=head1 INTERFACE

=head2 Run-Modes

=over 4

=cut

use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Log => qw(debug assert affirm ASSERT);
use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader Widget => qw(format_url);
use Krang::ClassLoader Message => qw(add_message);
use Krang::ClassLoader 'Publisher';
use Carp qw(croak);

use Krang::ClassLoader base => 'CGI';

sub setup {
    my $self = shift;
    $self->start_mode('show');
    $self->mode_param('rm');
    $self->tmpl_path('Workspace/');
    $self->run_modes([qw(
      show
      delete
      delete_checked
      goto_edit
      goto_log
      copy
      checkin
      checkin_checked
      deploy
      update_testing
    )]);

}

=item show

Shows the paging workspace view.  This is the default runmode and it
requires no parameters.

=cut

sub show {
    my $self = shift;
    my $query = $self->query;
    my $template = $self->load_tmpl("workspace.tmpl", 
                                    associate         => $query,
                                    die_on_bad_params => 0,
                                    global_vars => 1);

    my @found_desks = pkg('Desk')->find();
    my @desk_loop;

    foreach my $found_desk (@found_desks) {
        push (@desk_loop, { choice_desk_id => $found_desk->desk_id, choice_desk_name => $found_desk->name });
    }

    # setup sort selector
    my $sort = $query->param('krang_pager_sort_field') || 'type';
    $template->param('sort_select' => scalar
                     $query->popup_menu(-name => 'sort_select',
                                        -values => [ 'type',
                                                     'id',
                                                     'title',
                                                     'url',
                                                     'date' ],
                                        -labels => { type => 'Type',
                                                     id   => 'ID',
                                                     title => 'Title',
                                                     url   => 'URL',
                                                     date  => 'Date' },
                                        -default => $sort,
                                        -override => 1,
                                        -onchange => "do_sort(this.options[this.selectedIndex].value,0)",
                                       ));

    # permissions
    my %admin_perms = pkg('Group')->user_admin_permissions();
    $template->param(may_publish => $admin_perms{may_publish});

    # instance_name is used for preview window targeting
    my $instance_name = pkg('Conf')->instance;
    $instance_name =~ s![^\w]!_!g;
    $template->param(instance_name => $instance_name);

    # setup paging list of objects
    my $pager = pkg('HTMLPager')->new
      (
       cgi_query   => $query,
       use_module  => pkg('Workspace'),
       columns     => [ 'id', 'version', 'url', 'title', 'story_type', 
                        'thumbnail',
                        'command_column', 'checkbox_column'],
       columns_sortable => [ ],
       command_column_commands => [ 'log', 'edit' ],
       command_column_labels => { edit => 'Edit',
                                  log  => 'Log' },
       id_handler  => sub { $self->_obj2id( @_ ) },
       row_handler => sub { $self->_row_handler(@_,\@desk_loop) },
      );

    # Run the pager
    $pager->fill_template($template);
    return $template->output;
}

sub _row_handler {
    my ($self, $row, $obj, $desk_loop) = @_;
    $row->{desk_loop} = $desk_loop;

    if ($obj->isa('Krang::Story')) {
        $row->{story_id} = $obj->story_id;
        $row->{id} = $self->_obj2id($obj);
        $row->{title} = $obj->title;
        $row->{story_type} = $obj->class->display_name;
        $row->{is_story} = 1;
        $row->{url} =format_url(url    => $obj->url,
                                linkto => 
                                "javascript:preview_story(".$obj->story_id.")",
                                length => 50);
    } elsif ($obj->isa('Krang::Media')) {
        $row->{media_id} = $obj->media_id;
        $row->{id} = $self->_obj2id($obj);
        $row->{title} = $obj->title;
        $row->{thumbnail} = $obj->thumbnail_path(relative => 1);
        $row->{is_media} = 1;
        $row->{url} =format_url(url    => $obj->url,
                                linkto => 
                                "javascript:preview_media(".$obj->media_id.")",
                                length => 50);
    } else {
        $row->{template_id} = $obj->template_id;
        $row->{id} = $self->_obj2id($obj);
        $row->{title} = $obj->filename;
        $row->{is_template} = 1;
        $row->{url} = format_url(url    => $obj->url,
                                 length => 50);
        $row->{testing} = $obj->testing;
    }

    # setup version, used by all type
    $row->{version} = $obj->version;

    # permissions, used by everyone
    $row->{may_edit} = $obj->may_edit;
}

=item delete

Deletes a single object.  Requires an 'id' parameter of the form
'type_id'.

=cut

sub delete {
    my $self = shift;
    my $query = $self->query;
    my $obj = $self->_id2obj($query->param('id'));
    add_message('deleted_obj',
                type => ($obj->isa('Krang::Story') ? 'Story' : 
                         ($obj->isa('Krang::Media') ? 'Media' :
                          'Template')));
    $obj->delete;
    return $self->show;
}

=item deploy

Deploys a single template.  Requires an 'id' parameter of the form
'type_id'.

=cut

sub deploy {
    my $self = shift;
    my $query = $self->query;
    my $obj = $self->_id2obj($query->param('id'));
    add_message('deployed', id => $obj->template_id);
    my $publisher = pkg('Publisher')->new();
    $publisher->deploy_template(template => $obj);
    $obj->checkin;
    return $self->show;
}

=item copy

Copies an object.  Will redirect to the appropriate edit screen with
the copy loaded for editing.

=cut

sub copy {
    my $self = shift;
    my $query = $self->query;
    my $obj = $self->_id2obj($query->param('id'));
    
    # redirect as appropriate
    if ($obj->isa('Krang::Story')) {
        $self->header_props(-uri => 'story.pl?rm=copy&story_id=' .
                            $obj->story_id);
    } elsif ($obj->isa('Krang::Media')) {
        $self->header_props(-uri => 'media.pl?rm=copy&media_id=' .
                            $obj->media_id);
    } else {
        $self->header_props(-uri => 'template.pl?rm=copy&template_id=' .
                            $obj->template_id);
    }
    
    $self->header_type('redirect');
    return "";
}

=item delete_checked

Deletes a list of checked objects.  Requires an 'id' parameter of the form
'type_id'.

=cut

sub delete_checked {
    my $self = shift;
    my $query = $self->query;
    add_message('deleted_checked');
    foreach my $obj (map { $self->_id2obj($_) }
                     $query->param('krang_pager_rows_checked')) {
        $obj->delete;
    }
    return $self->show;
}

=item checkin 

Checks in object (to specified desk for stories)

=cut

sub checkin {
    my $self = shift;
    my $query = $self->query;
    my $obj = $self->_id2obj($query->param('id'));

    if ($obj->isa('Krang::Story')) {
        my $select = 'checkin_to_'.$query->param('id');
        $obj->checkin();
        my $result = $obj->move_to_desk($query->param($select));
        my $id = $obj->story_id;
        $id =~ s/story_//;
        $result ? add_message("moved_story", id => $id) : add_message("story_cant_move", id => $query->param('id'));

    } elsif ($obj->isa('Krang::Media')) {
        add_message("checkin_media", id => $obj->media_id);
        $obj->checkin();
    } else {
        add_message("checkin_template", id => $obj->template_id);
        $obj->checkin();
    }

    return $self->show;
}

=item update_testing

Changes the testing flag for a template object.

=cut

sub update_testing {
    my $self = shift;
    my $query = $self->query;
    my $obj = $self->_id2obj($query->param('id'));
    my $val = $query->param('testing_' . $query->param('id'));

    if ($val) {
        $obj->mark_for_testing;
        add_message('marked_for_testing', id => $obj->template_id);
    } else {
        $obj->unmark_for_testing;
        add_message('unmarked_for_testing', id => $obj->template_id);
    }

    return $self->show;
}


=item checkin_checked

Checks in checked objects (to specified desk for stories).

=cut
                                                                               
sub checkin_checked {
    my $self = shift;
    my $query = $self->query;
    foreach my $obj (map { $self->_id2obj($_) }
                     $query->param('krang_pager_rows_checked')) {
        if ($obj->isa('Krang::Story')) {
            my $select = 'checkin_to_story_'.$obj->story_id;
            $obj->checkin();
            my $result = $obj->move_to_desk($query->param($select));
            my $id = $obj->story_id;
            $id =~ s/story_//;
            $result ? add_message("moved_story", id => $id) : add_message("story_cant_move", id => $obj->story_id);
        } elsif ($obj->isa('Krang::Media')) {
            add_message("checkin_media", id => $obj->media_id);
            $obj->checkin();
        } else {
            add_message("checkin_template", id => $obj->template_id);
            $obj->checkin();
        }
    }
                                                                               
    return $self->show;
}

=item goto_edit

Redirects to the appropriate edit screen for this object.

=cut

sub goto_edit {
    my $self = shift;
    my $query = $self->query;
    my $obj = $self->_id2obj($query->param('id'));

    # redirect as appropriate
    if ($obj->isa('Krang::Story')) {
        $self->header_props(-uri => 'story.pl?rm=edit&story_id=' .
                            $obj->story_id);
    } elsif ($obj->isa('Krang::Media')) {
        $self->header_props(-uri => 'media.pl?rm=edit&media_id=' .
                            $obj->media_id);
    } else {
        $self->header_props(-uri => 'template.pl?rm=edit&template_id=' .
                            $obj->template_id);
    }
    
    $self->header_type('redirect');
    return "";
}

=item goto_log

Redirects to the history viewer for this object.

=cut

sub goto_log {
    my $self = shift;
    my $query = $self->query;
    my $obj = $self->_id2obj($query->param('id'));

    # redirect as appropriate
    my $id_param;
    if ($obj->isa('Krang::Story')) {
        $id_param = 'story_id=' . $obj->story_id;
    } elsif ($obj->isa('Krang::Media')) {
        $id_param = 'media_id=' . $obj->media_id;
    } else {
        $id_param = 'template_id=' . $obj->template_id;
    }

    my $uri = "history.pl?${id_param}&history_return_script=workspace.pl&history_return_params=rm&history_return_params=show";
    
    # mix in pager params for return
    foreach my $name (grep { /^krang_pager/ } $query->param) {
        $uri .= "&history_return_params=${name}&history_return_params=" . 
          $query->param($name);
    }

    $self->header_props(-uri => $uri);
    $self->header_type('redirect');
    return "";
}


#
# Utility functions
#

# transform object into a type_id pair
sub _obj2id {
    my $self = shift;

    my $obj = shift;
    return "story_"    . $obj->story_id    if $obj->isa('Krang::Story');
    return "media_"    . $obj->media_id    if $obj->isa('Krang::Media');
    return "template_" . $obj->template_id;
}

# transform type_id into an object
sub _id2obj {
    my $self = shift;

    my ($type, $id) = $_[0] =~ /^([^_]+)_(.*)$/;
    croak("Unable to find type and id in '$_[0]'")
      unless $type and $id;

    my $obj;
    if ($type eq 'story') {
        ($obj) = pkg('Story')->find(story_id => $id);
    } elsif ($type eq 'media') {
        ($obj) = pkg('Media')->find(media_id => $id);
    } else {
        ($obj) = pkg('Template')->find(template_id => $id);
    }
    croak("Unable to load $type $id")
      unless $obj;
    return $obj;
}

1;

=back

=cut
