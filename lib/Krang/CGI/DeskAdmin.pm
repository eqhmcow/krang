package Krang::CGI::DeskAdmin;
use base qw(Krang::CGI);
use strict;
use warnings;

use Carp qw(croak);
use Krang::Desk;
use Krang::Message qw(add_message);

=head1 NAME

Krang::CGI::DeskAdmin - web interface to create, delete and  
reorder Krang::Desks.

=head1 SYNOPSIS
  
  use Krang::CGI::DeskAdmin;
  my $app = Krang::CGI::DeskAdmin->new();
  $app->run();

=head1 DESCRIPTION

Krang::CGI::DeskAdmin provides a form in which users can 
add a new desk, delete current desks, or reorder current desks.

=head1 INTERFACE

Following are descriptions of all the run-modes provided by
Krang::CGI::DeskAdmin.

=cut

# setup runmodes
sub setup {
    my $self = shift;

    $self->start_mode('edit');
    
    $self->run_modes([qw(
                            edit
                            add
                            reorder
                            delete
                    )]);

    $self->tmpl_path('DeskAdmin/');    
}

=over 

=item edit

Displays list of current desks, as well as a place to add a
new desk 

=cut

sub edit {
    my $self = shift;
    my $error = shift || '';
    my $q = $self->query;
    my $template = $self->load_tmpl('edit.tmpl', associate => $q);
    $template->param( $error => 1 ) if $error;

    my $total_desks = Krang::Desk->find('count' => 1);
    $template->param( 'total_desks' => $total_desks );
    my @existing_desks = get_existing_desks($total_desks);
    $template->param( 'existing_desk_loop' => \@existing_desks ) if @existing_desks;
   
     $template->param( 'order_selector' => scalar 
                        $q->popup_menu( -name    => 'order',
                                            -values => [1 ..($total_desks + 1) ],
                                            -default => ($total_desks + 1) )); 
    return $template->output; 
}

sub get_existing_desks {
    my $total_desks = shift;
    my @desks = Krang::Desk->find();
    my @existing_desk_loop = ();

    foreach my $desk (@desks) {
        my @desk_count_loop;
        my $count;
        for ($count = 1; $count <= $total_desks; $count++) {
            my $selected = ($desk->order == $count) ? 1 : 0;
            push (@desk_count_loop, { count => $count, selected => $selected });
        }

        push (@existing_desk_loop, {    'desk_id' => $desk->desk_id,
                                        'name' => $desk->name,
                                        'desk_count_loop' => \@desk_count_loop
                                    } );
    }
    
    return @existing_desk_loop;
}

=item add() 

Commits new desk to the database.

=cut

sub add {
    my $self = shift;
    my $q = $self->query();

    if (not $q->param('name')) {
        add_message('no_name');
        return $self->edit('no_name');
    } 

    Krang::Desk->new(   name => $q->param('name'),
                        order => $q->param('order') );

    add_message('desk_added');
    return $self->edit();

}

=item reorder()

Reorders desk order in the database.

=cut

sub reorder {
    my $self = shift;
    my $q = $self->query();

    my @desks;

    my @param_names = $q->param;
    foreach my $index_name ( @param_names ) {
        if ($index_name =~ /order_\d*/) {
        print STDERR $index_name."\n";
            my $desk_id = $index_name;
            $desk_id =~ s/order_//;
            push (@desks, $desk_id);
            push (@desks, $q->param($index_name));
        }
    }


    Krang::Desk->reorder(@desks);

    add_message('desks_reordered');
    return $self->edit();
}

=item delete()

Deletes selected desks from the database.

=cut

sub delete {
    my $self = shift;
    my $q = $self->query();
    my @delete_list = ( $q->param('desk_delete_list') );
                                                                                 
    unless (@delete_list) {
        add_message('missing_desk_delete_list');
        return $self->edit();
    }
                                                                                 
    foreach my $desk_id (@delete_list) {
        Krang::Desk->delete($desk_id);
    }
                                                                                 
    add_message('deleted_selected');
    return $self->edit();
}

=back

=cut

1;
