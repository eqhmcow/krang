package Krang::CGI::ListGroup;
use base qw(Krang::CGI);
use strict;
use warnings;

=head1 NAME

Krang::CGI::ListGroup - web interface to manage list groups and list
contents.


=head1 SYNOPSIS

  use Krang::CGI::ListGroup;
  my $app = Krang::CGI::ListGroup->new();
  $app->run();


=head1 DESCRIPTION

Krang::CGI::ListGroup provides a web-based system through which users can
view Krang::ListGroups and edit the contents of the Krang::Lists contained
in each.


=head1 INTERFACE

Following are descriptions of all the run-modes
provided by Krang::CGI::ListGroup.

The default run-mode (start_mode) for Krang::CGI::ListGroup
is 'search'.

=head2 Run-Modes

=over 4

=cut


use Krang::ListGroup;
use Krang::List;
use Krang::Message qw(add_message);
use Krang::HTMLPager;
use Krang::Log qw(debug info critical);
use Carp;

##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
    my $self = shift;

    $self->start_mode('search');

    $self->run_modes([qw(
                         search
                         edit
                         save
                         save_stay
                         add
                         modify_selected
                         delete_selected
                        )]);

    $self->tmpl_path('ListGroup/');
}




##############################
#####  RUN-MODE METHODS  #####
##############################




=item search

This run-mode lists all list groups and allows users to search for 
list groups based on the list group name.

From this mode users may go to the list group editing screen.

This run-mode expects an optional parameters "search_filter"
which is expected to contain the text string which is used to 
query groups.

=cut


sub search {
    my $self = shift;

    my $q = $self->query();

    my $t = $self->load_tmpl("list_view.tmpl", associate=>$q, loop_context_vars=>1);

    # Do simple search based on search field
    my $search_filter = $q->param('search_filter') || '';
    my %find_params;
    $find_params{name_like} = '%'.$search_filter.'%' if $search_filter;

    # Configure pager
    my $pager = Krang::HTMLPager->new(
                                      cgi_query => $q,
                                      persist_vars => {
                                                       rm => 'search',
                                                       search_filter => $search_filter,
                                                      },
                                      use_module => 'Krang::ListGroup',
                                      find_params => { %find_params },
                                      columns => [qw(name command_column )],
                                      column_labels => {
                                                        name => 'List Group Name',
                                                       },
                                      columns_sortable => [qw( name )],
                                      command_column_commands => [qw( edit_list_group )],
                                      command_column_labels => {edit_list_group => 'Edit'},
                                      row_handler => sub {
                                          $_[0]->{name} = $_[1]->name();
                                      },
                                      id_handler => sub { return $_[0]->list_group_id },
                                     );

    # Run pager
    $t->param(pager_html =>  $pager->output());

    # Propagate other params
    $t->param(row_count => $pager->row_count());

    return $t->output();
}



=item add

Commit new Krang::ListItem into the database.

=cut


sub add {
    my $self = shift;

}



=item edit

Display "edit list group" screen through which lists may be modified.


=cut


sub edit {
    my $self = shift;

    my $q = $self->query();
    my $list_group_id = $q->param('list_group_id');
    my ( $lg ) = Krang::ListGroup->find( list_group_id => $list_group_id );

    # Did we get our group?  Presumbably, users get here from a list.  IOW, there is 
    # no valid (non-fatal) case where a user would be here with an invalid group_id
    die ("No such list_group_id '$list_group_id'") unless (defined($lg));
   
     my $t = $self->load_tmpl("edit.tmpl", associate=>$q, loop_context_vars=>1); 
    my @lists = Krang::List->find( list_group_id => $lg->list_group_id ); 
  
    my $js = 'lists = new Array();';
  
    my $list_names= join(',', map { $_->name } @lists);
    $js .= "\nlists = [$list_names];";

    my $js .= "\nlist_data = new Array();";
    my $list_levels = scalar @lists;

    foreach my $list (@lists) {
             
    } 
    
    $t->param( 'js_list_arrays' => $js ); 
    $t->param( 'list_group_description' => $lg->description );
 
    return $t->output();
}



=item save

Save a

=cut


sub save {
    my $self = shift;

    my $q = $self->query();

    return $self->search();
}





=item save_stay

Same as mode "save", except user is returned to the edit screen.

=cut


sub save_stay {
    my $self = shift;

    my $q = $self->query();

    return $self->edit();
}

=item delete_selected

Delete the selected list item.

=cut


sub delete_selected {
    my $self = shift;

    my $q = $self->query();

    return $self->search();
}






#############################
#####  PRIVATE METHODS  #####
#############################

1;


=back

=cut

