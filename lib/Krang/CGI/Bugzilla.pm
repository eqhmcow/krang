package Krang::CGI::Bugzilla;
use base qw(Krang::CGI);
use strict;
use warnings;

use Carp qw(croak);
use WWW::Bugzilla;
use Krang::Message qw(add_message);
use Krang::Session qw(%session);
use Krang::Conf qw(BugzillaServer BugzillaEmail BugzillaPassword BugzillaComponent);

=head1 NAME

Krang::CGI::Bugzilla - web interface to input bugs directly from Krang 
into a bugzilla server.

=head1 SYNOPSIS
  
  use Krang::CGI::Bugzilla;
  my $app = Krang::CGI::Bugzilla->new();
  $app->run();

=head1 DESCRIPTION

Krang::CGI::Bugzilla provides a form in which users can enter
information about what they were doing when a bug occurred.
Also adds a dump of the session as an attachment to the bug.

=head1 INTERFACE

Following are descriptions of all the run-modes provided by
Krang::CGI::Bugzilla.

=cut

# setup runmodes
sub setup {
    my $self = shift;

    $self->start_mode('edit');
    
    $self->run_modes([qw(
                            edit
                            commit
                    )]);

    $self->tmpl_path('Bugzilla/');    
}

=over 

=item edit

Displays a user-editable bug form.

=cut

sub edit {
    my $self = shift;
    my $q = $self->query;
    my $template = $self->load_tmpl('edit.tmpl', associate => $q);

    return $template->output; 
}

=item commit() 

Commits bug to the bugzilla server.

=cut

sub commit {
    my $self = shift;
    my $q = $self->query();

    my $bz = WWW::Bugzilla->new(    server => BugzillaServer,
                                    email => BugzillaEmail,
                                    password => BugzillaPassword,
                                    product => 'Krang' );

    $bz->component(BugzillaComponent);    
    $bz->summary($q->param('summary'));

    my $description = $q->param('description');
    $description .= "\n\nReproducability: ".$q->param('reproduce');
    $description .= "\n\nSteps to reproduce:\n".$q->param('steps');
    $description .= "\n\nActual Results: ".$q->param('actual_results') if $q->param('actual_results');
    $description .= "\n\nExpected Results: ".$q->param('expected_results') if $q->param('expected_results');

    $bz->description($description);    
    $bz->severity($q->param('bug_severity'));
    
    $bz->commit();
 
    return $self->edit();
}

=back

=cut

1;
