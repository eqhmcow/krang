package Krang::CGI::Bugzilla;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => qw(CGI);
use strict;
use warnings;

use Carp qw(croak);
use Data::Dumper;
use File::Path;
use File::Spec::Functions qw(catdir catfile);
use File::Temp qw/ tempdir /;
use WWW::Bugzilla;
use Krang::ClassLoader Message => qw(add_message add_alert);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Conf =>
  qw(KrangRoot BugzillaServer BugzillaEmail BugzillaPassword BugzillaComponent EnableBugzilla);

=head1 NAME

Krang::CGI::Bugzilla - web interface to input bugs directly from Krang 
into a bugzilla server.

=head1 SYNOPSIS
  
  use Krang::ClassLoader 'CGI::Bugzilla';
  my $app = pkg('CGI::Bugzilla')->new();
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

    $self->run_modes(
        [
            qw(
              edit
              commit
              )
        ]
    );

    $self->tmpl_path('Bugzilla/');
}

=over 

=item edit

Displays a user-editable bug form.  If 'ise' is set to a true value
then the user is informed that something just went boom.

=cut

sub edit {
    my $self     = shift;
    my $error    = shift || '';
    my $q        = $self->query;
    my $template = $self->load_tmpl('edit.tmpl', associate => $q);
    $template->param(bug_page => 1);
    $template->param($error                                      => 1) if $error;
    $template->param("reproduce_" . $q->param('reproduce')       => 1) if $q->param('reproduce');
    $template->param("bug_severity_" . $q->param('bug_severity') => 1) if $q->param('reproduce');
    return $template->output;
}

=item commit() 

Commits bug to the bugzilla server.

=cut

sub commit {
    my $self = shift;
    my $q    = $self->query();

    if (not $q->param('summary')) {
        add_alert('no_summary');
        return $self->edit('no_summary');
    } elsif (not $q->param('description')) {
        add_alert('no_description');
        return $self->edit('no_description');
    }

    my $bz = WWW::Bugzilla->new(
        server   => BugzillaServer,
        email    => BugzillaEmail,
        password => BugzillaPassword,
        product  => 'Krang'
    );

    $bz->component(BugzillaComponent);
    $bz->summary($q->param('summary'));

    my $description = $q->param('description');
    $description .= "\n\nReproducability: " . $q->param('reproduce');
    $description .= "\n\nSteps to reproduce:\n" . $q->param('steps');
    $description .= "\n\nActual Results: " . $q->param('actual_results')
      if $q->param('actual_results');
    $description .= "\n\nExpected Results: " . $q->param('expected_results')
      if $q->param('expected_results');

    $bz->description($description);
    $bz->severity($q->param('bug_severity'));

    my $bug_num = $bz->commit();

    # create tempfile for storage of session dump
    my $path = tempdir(DIR => catdir(KrangRoot, 'tmp'));
    my $temp_file = catfile($path, 'session_dump.txt');
    open(FILE, ">$temp_file")
      || croak(__PACKAGE__ . "->commit() - Unable to open $temp_file for writing");
    print FILE Data::Dumper->Dump([\%session], ['session']);
    close FILE;

    $bz->add_attachment(
        filepath    => $temp_file,
        description => 'Session Dump Text File'
    );

    # remove tempfile and path
    rmtree($path);

    add_message('bug_added', bug_num => $bug_num);
    return $self->edit('bug_added');
}

=back

=cut

1;
