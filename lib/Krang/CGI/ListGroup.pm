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
use Krang::ListItem;
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
                                      columns => [qw(name description command_column )],
                                      column_labels => {
                                                        name => 'List Group Name', 
                                                        description => 'Description'
                                                       },
                                      columns_sortable => [qw( name )],
                                      command_column_commands => [qw( edit_list_group )],
                                      command_column_labels => {edit_list_group => 'Edit'},
                                      row_handler => sub {
                                            $_[0]->{name} = $_[1]->name();
                                            $_[0]->{description} = $_[1]->description();
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
   
     my $t = $self->load_tmpl("edit.tmpl", associate=>$q, loop_context_vars=>1, die_on_bad_params => 0); 
    my @lists = Krang::List->find( list_group_id => $lg->list_group_id ); 
  
    my $list_names= join(',', map { "'".$_->name."'" } @lists);
    my $js = "\nlists = new Array($list_names);";

    $js .= "\nlist_data = new Array();";
    my $list_levels = scalar @lists;

    my @list_loop;

    my $count = 1;
   
    foreach my $list (@lists) {
        my @list_items = Krang::ListItem->find( list_id => $list->list_id );

        my @list_item_loop;
        my $first = 1;

        # set up crazy javascript data structure
        foreach my $li (@list_items) {
            my $has_parent = 1;
            my @parents;
            my $c_li = $li;
            while ($has_parent) {
                if ($c_li->parent_list_item_id) {
                    $c_li = (Krang::ListItem->find( list_item_id => $c_li->parent_list_item_id ))[0]; 
                    unshift(@parents,($c_li->order - 1));
                    
                } else {
                    push(@parents,($li->order - 1)); 
                    $has_parent = 0;
                }
            }
            @parents = map { "[".$_."]" } @parents;

            my $parent_string = join('', @parents);
            my $li_data = $li->data;
            $li_data =~ s/"/''/g;
            chomp $li_data;

            $js .= "\nlist_data$parent_string = new Array();";
            $js .= "\nlist_data$parent_string\['__data__'] = ".'"'.$li_data.'";';
            $js .= "\nlist_data$parent_string\['__id__'] = '".$li->list_item_id."';";
 
            # prepopulate first list 
            push (@list_item_loop, { data => $li->data, order => ($li->order - 1), first => $first }) if ($count == 1);

        }

        
        if ($count == 1) {
            push( @list_loop, { list_id => $list->list_id, list_name => $list->name, list_item_loop => \@list_item_loop, list_count => $count++ } );         
        } else {
            push( @list_loop, { list_id => $list->list_id, list_name => $list->name, list_count => $count++} ); 
        }
    } 
   
    $t->param( 'list_levels' => $list_levels ); 
    $t->param( 'list_group_name' => $lg->name ); 
    $t->param( 'list_loop' => \@list_loop ); 
    $t->param( 'js_list_arrays' => $js ); 
    $t->param( 'list_group_description' => $lg->description );
    $t->param( 'list_group_id' => $list_group_id ); 
    return $t->output();
}



=item save

Save altered list items and ListGroup description

=cut


sub save {
    my $self = shift;

    my $q = $self->query();
    my $changes = $q->param('changes');
    my @change_list = split('%\^%', $changes);
    my %new_ids;
    foreach my $c (@change_list) {
        my @c_params = split('#&#', $c);
        if ($c_params[1] eq 'new') {
            my ($data,$order,$lid,$pid) = split('\^\*\^', $c_params[2]);
            if ($pid =~ /^new_\S+/) {
                $pid = $new_ids{$pid};
            }
            my %s_params;
            $s_params{data} = $data;
            $s_params{order} = $order;
            $s_params{list} = (Krang::List->find( list_id => $lid))[0];
            $s_params{parent_list_item} = (Krang::ListItem->find( list_item_id => $pid))[0] if $pid; 
            my $new_item = Krang::ListItem->new( %s_params );
            $new_item->save();
            $new_ids{$c_params[0]} = $new_item->list_item_id;
        } else {
            my $list_item_id = $c_params[0];
            if ($c_params[0] =~ /^new_\S+/) {
                $list_item_id = $new_ids{$c_params[0]};
            }
            
            my ($item) = Krang::ListItem->find( list_item_id => $list_item_id );

            if ($c_params[1] eq 'delete') {
                $item->delete;
            } elsif ($c_params[1] eq 'replace') {
                $item->data($c_params[2]);
                $item->save;
            } elsif ($c_params[1] eq 'move') {
                $item->order($c_params[2]);
                $item->save; 
            }
        }
    }

    # now handle list_group_description
    if ($q->param('list_group_description')) {
        my ($lg) = Krang::ListGroup->find(list_group_id => $q->param('list_group_id'));
        $lg->description($q->param('list_group_description'));
        $lg->save;
    }

    add_message('lists_saved');

    if ($q->param('stay')) {
        return $self->edit();
    } else {
        return $self->search();
    }
}


#############################
#####  PRIVATE METHODS  #####
#############################

1;


=back

=cut

