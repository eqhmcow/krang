package Krang::CGI::Group;
use base qw(Krang::CGI);
use strict;
use warnings;




=head1 NAME

Krang::CGI::Group - web interface to manage permission groups


=head1 SYNOPSIS

  use Krang::CGI::Group;
  my $app = Krang::CGI::Group->new();
  $app->run();


=head1 DESCRIPTION

Krang::CGI::Group provides a web-based system through which users can
add, modify or delete permission groups from a Krang instance.


=head1 INTERFACE

Following are descriptions of all the run-modes
provided by Krang::CGI::Group.

The default run-mode (start_mode) for Krang::CGI::Group
is 'search'.

=head2 Run-Modes

=over 4

=cut


use Krang::Group;
use Krang::Widget;
use Krang::Message qw(add_message);
use Krang::HTMLPager;
use Krang::Pref;
use Krang::Session qw(%session);
use Carp;


# Fields in a group object
use constant GROUP_PROTOTYPE => {
                                 group_id            => '',
                                 name                => '',
                                 categories          => {},
                                 desks               => {},
                                 may_publish         => 1,
                                 admin_users         => 1,
                                 admin_users_limited => 1,
                                 admin_groups        => 1,
                                 admin_contribs      => 1,
                                 admin_sites         => 1,
                                 admin_categories    => 1,
                                 admin_jobs          => 1,
                                 admin_desks         => 1,
                                 asset_story         => 'edit',
                                 asset_media         => 'edit',
                                 asset_template      => 'edit'
                                };



##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
    my $self = shift;

    $self->start_mode('search');

    $self->run_modes([qw(
                         search
                         add
                         edit
                         save
                         save_stay
                         cancel
                         delete
                         delete_selected
                         edit_categories
                         add_category
                         delete_category
                        )]);

    $self->tmpl_path('Group/');
}




##############################
#####  RUN-MODE METHODS  #####
##############################




=item search

This run-mode lists all groups and allows users to search for groups
based on the group name.

From this mode users may edit a group, add a new group, or delete a set of groups.

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

    # Configure pager
    my $pager = Krang::HTMLPager->new(
                                      cgi_query => $q,
                                      persist_vars => {
                                                       rm => 'search',
                                                       search_filter => $search_filter,
                                                      },
                                      use_module => 'Krang::Group',
                                      find_params => { simple_search => $search_filter },
                                      columns => [qw(name may_publish command_column checkbox_column)],
                                      column_labels => {
                                                        name => 'Group Name',
                                                        may_publish => 'Publish?',
                                                       },
                                      columns_sortable => [qw( name may_publish )],
                                      command_column_commands => [qw( edit_group )],
                                      command_column_labels => {edit_group => 'Edit'},
                                      row_handler => sub {
                                          $_[0]->{name} = $_[1]->name();
                                          $_[0]->{may_publish} = $_[1]->may_publish() ? 'Yes' : 'No';
                                      },
                                      id_handler => sub { return $_[0]->group_id },
                                     );

    # Run pager
    $t->param(pager_html =>  $pager->output());

    # Propagate other params
    $t->param(row_count => $pager->row_count());

    return $t->output();
}



=item add

Description of run-mode 'add'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub add {
    my $self = shift;
    my %ui_messages = ( @_ );

    my $q = $self->query();
    my $t = $self->load_tmpl("edit_view.tmpl", associate=>$q);
    $t->param(add_mode => 1);
    $t->param(%ui_messages) if (%ui_messages);

    # Make new Group, but don't save it
    my $g = Krang::Group->new();

    # Stash it in the session for later
    $session{EDIT_GROUP} = $g;

    # Convert Krang::Contrib object to tmpl data
    my $group_tmpl = $self->get_group_tmpl($g);

    # Propagate to template
    $t->param($group_tmpl);

    return $t->output();
}





=item edit

Description of run-mode 'edit'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub edit {
    my $self = shift;
    my %ui_messages = ( @_ );

    my $q = $self->query();

    my $group_id = $q->param('group_id');
    my ( $g ) = Krang::Group->find( group_id=>$group_id);

    # Did we get our group?  Presumbably, users get here from a list.  IOW, there is 
    # no valid (non-fatal) case where a user would be here with an invalid group_id
    die ("No such group_id '$group_id'") unless (defined($g));

    # Stash it in the session for later
    $session{EDIT_GROUP} = $g;

    my $t = $self->load_tmpl("edit_view.tmpl", associate=>$q);
    $t->param(%ui_messages) if (%ui_messages);


    # For testing
    return $t->output();


    # Convert Krang::Group object to tmpl data
    my $group_tmpl = $self->get_group_tmpl($g);

    # Propagate to template
    $t->param($group_tmpl);

    return $t->output();
}





=item save

Description of run-mode 'save'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub save {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item save_stay

Description of run-mode 'save_stay'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub save_stay {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item cancel

Description of run-mode 'cancel'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub cancel {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item delete

Description of run-mode 'delete'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub delete {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item delete_selected

Delete a set of groups, specified by check-mark
on the "Group List" screen provided by the "search" 
run-mode.  Return to the "search" run-mode.

This mode expects the query param "krang_pager_rows_checked"
to contain an array of group_id values which correspond
to group records to be deleted.


=cut


sub delete_selected {
    my $self = shift;

    my $q = $self->query();
    my @group_delete_list = ( $q->param('krang_pager_rows_checked') );
    $q->delete('krang_pager_rows_checked');

    # No selected groups?  Just return to list view without any message
    return $self->search() unless (@group_delete_list);

    foreach my $id (@group_delete_list) {
        my ($g) = Krang::Group->find(group_id=>$id);
        $g->delete($id) if ($g);
    }

    add_message('message_selected_deleted');
    return $self->search();
}





=item edit_categories

Description of run-mode 'edit_categories'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub edit_categories {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item add_category

Description of run-mode 'add_category'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub add_category {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item delete_category

Description of run-mode 'delete_category'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub delete_category {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}







#############################
#####  PRIVATE METHODS  #####
#############################

# Return a hashref based on group properties, suitible
# to be passed to an HTML::Template edit/add screen.
# If a $group object is supplied, use its properties
# for default values.
sub get_group_tmpl {
    my $self = shift;
    my $g = shift || 0;

    my $q = $self->query();

    my %group_tmpl = ( %{&GROUP_PROTOTYPE} );

    # For each group prop, convert to HTML::Template compatible data
    foreach my $gf (keys(%group_tmpl)) {
        # Handle radio groups
        if (grep { $gf eq $_ } qw(asset_story asset_media asset_template)) {
            delete($group_tmpl{$gf});
            next;
        }

        # Handle compound properties
        if (grep { $gf eq $_ } qw(categories desks)) {
            delete($group_tmpl{$gf});
            next;
        }

        # Handle simple (text) fields
        my $query_val = $q->param($gf);
        if (defined($query_val)) {
            # Overlay query params
            $group_tmpl{$gf} = $query_val;
        } else {
            $group_tmpl{$gf} = $g->$gf if (ref($g));
        }
    }

    # Return a reference to the tmpl-compat data
    return \%group_tmpl;
}




1;


=back


=head1 SEE ALSO

L<Krang::Group>, L<Krang::Widget>, L<Krang::Message>, L<Krang::HTMLPager>, L<Krang::Pref>, L<Krang::Session>, L<Carp>, L<Krang::CGI>

=cut


####  CREATED VIA:
#
#
#
# use CGI::Application::Generator;
# my $c = CGI::Application::Generator->new();
# $c->app_module_tmpl($ENV{HOME}.'/krang/templates/krang_cgi_app.tmpl');
# $c->package_name('Krang::CGI::Group');
# $c->base_module('Krang::CGI');
# $c->start_mode('search');
# $c->run_modes(qw(
#                  search
#                  add
#                  edit
#                  save
#                  save_stay
#                  cancel
#                  delete
#                  delete_selected
#                  edit_categories
#                  add_category
#                  delete_category
#                 ));
# $c->use_modules(qw/Krang::Group Krang::Widget Krang::Message Krang::HTMLPager Krang::Pref Krang::Session Carp/);
# $c->tmpl_path('Group/');

# print $c->output_app_module();
