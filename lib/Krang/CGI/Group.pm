package Krang::CGI::Group;
use base qw(Krang::CGI);
use strict;
use warnings;




=head1 NAME

Krang::CGI::Group - web interface to.....


=head1 SYNOPSIS

  use Krang::CGI::Group;
  my $app = Krang::CGI::Group->new();
  $app->run();


=head1 DESCRIPTION

Krang::CGI::Group provides a web-based system
through which users can.....


=head1 INTERFACE

Following are descriptions of all the run-modes
provided by Krang::CGI::Group.

The default run-mode (start_mode) for Krang::CGI::Group
is 'find'.

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

    $self->start_mode('find');

    $self->run_modes([qw(
                         find
                         add
                         edit
                         save
                         save_stay
                         cancel
                         delete
                         edit_categories
                         add_category
                         delete_category
                        )]);

    $self->tmpl_path('Group/');
}




##############################
#####  RUN-MODE METHODS  #####
##############################




=item find

Description of run-mode 'find'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub find {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
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
# $c->start_mode('find');
# $c->run_modes(qw(
#                  find
#                  add
#                  edit
#                  save
#                  save_stay
#                  cancel
#                  delete
#                  edit_categories
#                  add_category
#                  delete_category
#                 ));
# $c->use_modules(qw/Krang::Group Krang::Widget Krang::Message Krang::HTMLPager Krang::Pref Krang::Session Carp/);
# $c->tmpl_path('Group/');

# print $c->output_app_module();
