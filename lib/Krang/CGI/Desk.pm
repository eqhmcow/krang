package Krang::CGI::Desk;
use strict;
use warnings;

=head1 NAME

Krang::CGI::Desk - displays stories on a particular desk

=head1 SYNOPSIS

  use Krang::CGI::Desk;
  my $app = Krang::CGI::Desk->new();
  $app->run();

=head1 DESCRIPTION

This application manages display of stories on desks for Krang.

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
    $self->tmpl_path('Desk/');
    $self->run_modes([qw(
      show
      checkout 
      checkout_checked
      goto_edit
      goto_log
      goto_view
    )]);

}

=item show

Shows the paging desk view.  This is the default runmode and it
requires no parameters.

=cut

sub show {
    my $self = shift;
    my $query = $self->query;
    my $template = $self->load_tmpl("desk.tmpl", 
                                    associate         => $query,
                                    die_on_bad_params => 0);

    my $desk_id = $query->param('desk_id');
    my $desk = (Krang::Desk->find( desk_id => $desk_id))[0];
    $template->param( desk_name => $desk->name );
    $template->param( desk_id => $desk_id );

    # setup sort selector
    my $sort = $query->param('krang_pager_sort_field') || 'story_id';
    $template->param('sort_select' => scalar
                     $query->popup_menu(-name => 'sort_select',
                                        -values => [ 'story_id',
                                                     'title',
                                                     'url',
                                                     'cover_date' ],
                                        -labels => { story_id => 'ID',
                                                     title => 'Title',
                                                     url   => 'URL',
                                                     cover_date  => 'Cover Date' },
                                        -default => $sort,
                                        -override => 1,
                                        -onchange => "do_sort(this.options[this.selectedIndex].value,0)",
                                       ));

    # setup paging list of objects
    my $pager = Krang::HTMLPager->new
      (
       cgi_query   => $query,
       use_module  => 'Krang::Story',
       columns     => [ 'id', 'version', 'url', 'title', 'story_type', 
                        'command_column', 'checkbox_column'],
       columns_sortable => [ ],
       find_params => { desk_id => $desk_id },
       command_column_commands => [ 'log', 'view', 'edit' ],
       command_column_labels => {   view => 'View',
                                    edit => 'Edit',
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
    $row->{story_id} = $obj->story_id;
    $row->{id} = _obj2id($obj);
    $row->{title} = $obj->title;
    $row->{story_type} = $obj->class->display_name;
    $row->{url} = format_url(url    => $obj->url,
                             linkto => 
                             "javascript:preview_story($row->{id})",
                             length => 50);

    # setup version
    $row->{version} = $obj->version;
}

=item delete

Deletes a single object.  Requires an 'id'. 

=cut

sub delete {
    my $self = shift;
    my $query = $self->query;
    my $obj = _id2obj($query->param('id'));
    add_message('deleted_story');
    $obj->delete;
    return $self->show;
}

=item delete_checked

Deletes a list of checked objects.  

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

    $self->header_props(-uri => 'story.pl?rm=edit&story_id=' .
                        $obj->story_id);
    
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
    my $id_param = 'story_id=' . $obj->story_id;

    my $uri = "history.pl?${id_param}&history_return_script=desk.pl&history_return_params=rm&history_return_params=show";
    
    # mix in pager params for return
    foreach my $name (grep { /^krang_pager/ } $query->param) {
        $uri .= "&history_return_params=${name}&history_return_params=" . 
          $query->param($name);
    }

    $self->header_props(-uri => $uri);
    $self->header_type('redirect');
    return "";
}

=item goto_view
                                                                                
Redirects to the story view for this object.
                                                                                
=cut
                                                                                
sub goto_view {
    my $self = shift;
    my $query = $self->query;
    my $obj = _id2obj($query->param('id'));
                                                                                
    $self->header_props(-uri => 'story.pl?return_script=desk.pl&return_params=rm&return_params=show&rm=view&story_id=' .
                            $obj->story_id);
                                                                                
    $self->header_type('redirect');
    return "";

}


#
# Utility functions
#

sub _obj2id {
    my $obj = shift;
    return $obj->story_id;
}

# transform story_id into an object
sub _id2obj {
    my ($id) = shift;
    my $obj;
        ($obj) = Krang::Story->find(story_id => $id);
    croak("Unable to load story $id")
      unless $obj;
    return $obj;
}

1;

=back

=cut
