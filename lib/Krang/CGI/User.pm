package Krang::CGI::User;

=head1 NAME

Krang::CGI::User - 
Abstract of web application....


=head1 SYNOPSIS

  use Krang::CGI::User;
  my $app = Krang::CGI::User->new();
  $app->run();


=head1 DESCRIPTION

Overview of functionality and purpose of 
web application module Krang::CGI::User...

=cut


use strict;
use warnings;


use base qw/Krang::CGI/;


use Krang::History;
use Krang::HTMLPager;
use Krang::Log;
use Krang::Message;
use Krang::Pref;
use Krang::Session;
use Krang::User;




##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
	my $self = shift;

	$self->start_mode('search');

	$self->run_modes([qw/
		add
		cancel_add
		save_add
		save_stay_add
		delete
		delete_selected
		edit
		cancel_edit
		save_edit
		save_stay_edit
		search
		view
	/]);

	$self->tmpl_path('User/');

}


sub teardown {
	my $self = shift;
}



##############################
#####  RUN-MODE METHODS  #####
##############################


=head1 RUN MODES

=over 4


=item * add

Description of run-mode add...

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


=item * cancel_add

Description of run-mode cancel_add...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub cancel_add {
	my $self = shift;

	my $q = $self->query();

	return $self->dump_html();
}


=item * save_add

Description of run-mode save_add...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub save_add {
	my $self = shift;

	my $q = $self->query();

	return $self->dump_html();
}


=item * save_stay_add

Description of run-mode save_stay_add...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub save_stay_add {
	my $self = shift;

	my $q = $self->query();

	return $self->dump_html();
}


=item * delete

Description of run-mode delete...

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


=item * delete_selected

Description of run-mode delete_selected...

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


=item * edit

Description of run-mode edit...

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


=item * cancel_edit

Description of run-mode cancel_edit...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub cancel_edit {
	my $self = shift;

	my $q = $self->query();

	return $self->dump_html();
}


=item * save_edit

Description of run-mode save_edit...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub save_edit {
	my $self = shift;

	my $q = $self->query();

	return $self->dump_html();
}


=item * save_stay_edit

Description of run-mode save_stay_edit...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub save_stay_edit {
	my $self = shift;

	my $q = $self->query();

	return $self->dump_html();
}


=item * search

Description of run-mode search...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub search {
	my $self = shift;

	my $q = $self->query();

	return $self->dump_html();
}


=item * view

Description of run-mode view...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut

sub view {
	my $self = shift;

	my $q = $self->query();

	return $self->dump_html();
}




##############################
#####  PRIVATE METHODS   #####
##############################



=back

=head1 AUTHOR

Author of Module <author@module>


=head1 SEE ALSO

L<Krang::History>, L<Krang::HTMLPager>, L<Krang::Log>, L<Krang::Message>, L<Krang::Pref>, L<Krang::Session>, L<Krang::User>, L<Krang::CGI>

=cut



my $quip = <<END;
I do not feel obliged to believe that the same God who has endowed us
with sense, reason, and intellect has intended us to forgo their use.

-- Galileo Galilei 
END
