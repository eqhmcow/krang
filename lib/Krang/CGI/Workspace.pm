package Krang::CGI::Workspace;
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

use Krang::Session qw(%session);
use Krang::Log qw(debug assert affirm ASSERT);
use Krang::HTMLPager;
use Krang::Widget qw(format_url);
use Krang::Message qw(add_message);

use base 'Krang::CGI';

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
                                    die_on_bad_params => 0);

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

    # setup paging list of objects
    my $pager = Krang::HTMLPager->new
      (
       cgi_query   => $query,
       use_module  => 'Krang::Workspace',
       columns     => [ 'id', 'version', 'url', 'title', 'story_type', 
                        'thumbnail',
                        'command_column', 'checkbox_column'],
       columns_sortable => [ ],
       command_column_commands => [ 'log', 'edit' ],
       command_column_labels => { edit => 'Edit',
                                  log  => 'Log' },
       id_handler  => \&_obj2id,
       row_handler => \&_row_handler,
      );

    # Run the pager
    $pager->fill_template($template);
    return $template->output;
}

sub _row_handler {
    my ($row, $obj) = @_;
    if ($obj->isa('Krang::Story')) {
        $row->{story_id} = $obj->story_id;
        $row->{id} = _obj2id($obj);
        $row->{title} = $obj->title;
        $row->{story_type} = $obj->class->display_name;
        $row->{is_story} = 1;
        $row->{url} = format_url(url    => $obj->url,
                                 linkto => 
                                 "javascript:preview_story($row->{id})",
                                 length => 50);
    } elsif ($obj->isa('Krang::Media')) {
        $row->{media_id} = $obj->media_id;
        $row->{id} = _obj2id($obj);
        $row->{title} = $obj->title;
        $row->{thumbnail} = $obj->thumbnail_path(relative => 1);
        $row->{is_media} = 1;
        $row->{url} = format_url(url    => $obj->url,
                                 linkto => 
                                 "javascript:preview_media($row->{id})",
                                 length => 50);
    } else {
        $row->{template_id} = $obj->template_id;
        $row->{id} = _obj2id($obj);
        $row->{title} = $obj->filename;
        $row->{is_template} = 1;
        $row->{url} = format_url(url    => $obj->url,
                                 length => 50);
    }

    # setup version, used by all types
    $row->{version} = $obj->version;
}

=item delete

Deletes a single object.  Requires an 'id' parameter of the form
'type_id'.

=cut

sub delete {
    my $self = shift;
    my $query = $self->query;
    my $obj = _id2obj($query->param('id'));
    add_message('deleted_obj',
                type => ($obj->isa('Krang::Story') ? 'Story' : 
                         ($obj->isa('Krang::Media') ? 'Media' :
                          'Template')));
    $obj->delete;
    return $self->show;
}

=item copy

Copies an object.  Will redirect to the appropriate edit screen with
the copy loaded for editing.

=cut

sub copy {
    my $self = shift;
    my $query = $self->query;
    my $obj = _id2obj($query->param('id'));
    
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
    foreach my $obj (map { _id2obj($_) }
                     $query->param('krang_pager_rows_checked')) {
        $obj->delete;
    }
    return $self->show;
}

=item goto_edit

Redirects to the appropriate edit screen for this object.

=cut

sub goto_edit {
    my $self = shift;
    my $query = $self->query;
    my $obj = _id2obj($query->param('id'));

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
    my $obj = _id2obj($query->param('id'));

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
    my $obj = shift;
    return "story_"    . $obj->story_id    if $obj->isa('Krang::Story');
    return "media_"    . $obj->media_id    if $obj->isa('Krang::Media');
    return "template_" . $obj->template_id;
}

# transform type_id into an object
sub _id2obj {
    my ($type, $id) = $_[0] =~ /^([^_]+)_(.*)$/;
    croak("Unable to find type and id in '$_[0]'")
      unless $type and $id;

    my $obj;
    if ($type eq 'story') {
        ($obj) = Krang::Story->find(story_id => $id);
    } elsif ($type eq 'media') {
        ($obj) = Krang::Media->find(media_id => $id);
    } else {
        ($obj) = Krang::Template->find(template_id => $id);
    }
    croak("Unable to load $type $id")
      unless $obj;
    return $obj;
}

1;

=back

=cut
