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
use Krang::Message;
use Krang::HTMLPager;
use Krang::Pref;
use Krang::Session;
use Carp;



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
                                      row_handler => sub { $_[0]->{name} = $_[1]->name(); $_[0]->{may_publish} = $_[1]->may_publish() ? 'Yes' : 'No'; },
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

    my $q = $self->query();

    return $self->dump_html();
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

    my $q = $self->query();

    return $self->dump_html();
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

Description of run-mode 'delete_selected'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub delete_selected {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
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
