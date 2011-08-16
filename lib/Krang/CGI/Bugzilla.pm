package Krang::CGI::Bugzilla;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => qw(CGI);
use strict;
use warnings;

use Carp qw(croak);
use Data::Dumper;
use File::Path;
use File::Spec::Functions qw(catdir catfile);
use File::Basename qw(basename);
use File::Temp qw/ tempdir /;
use WWW::Bugzilla;
use Krang::ClassLoader Message => qw(add_message add_alert);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Conf =>
  qw(KrangRoot BugzillaServer BugzillaEmail BugzillaPassword BugzillaComponent EnableBugzilla);
use List::Util qw(first);

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
    $self->run_modes([qw( edit commit)]);
    $self->tmpl_path('Bugzilla/');

    # some ISEs can come from POST requests. In those cases we need to look at the URL's query 
    # string instead of the POST params or we won't know what's happening. The "ise" param is
    # always set if it's a redirect (an Apache ErrorDocument subrequest request)
    if( $self->query->url_param('ise') ) {
        $self->query->delete_all();
    }
}

=over 

=item edit

Displays a user-editable bug form. If 'ise' is set to a true value
then the user is informed that something just went boom.

=cut

sub edit {
    my $self     = shift;
    my $error    = shift || '';
    my $q        = $self->query;
    my $template = $self->load_tmpl('edit.tmpl', associate => $q);
    $template->param(
        bug_page        => 1,
        progress_screen => $self->is_progress_screen,
    );
    $template->param($error                                      => 1) if $error;
    $template->param("reproduce_" . $q->param('reproduce')       => 1) if $q->param('reproduce');
    $template->param("bug_severity_" . $q->param('bug_severity') => 1) if $q->param('reproduce');
    return $template->output;
}

sub is_progress_screen {
    my $self = shift;
    my $query = $self->query;
    return 1 if $query->param('progress_screen');
    return 0 unless $ENV{REDIRECT_SCRIPT_NAME};
    my %progress_screens = (
        'publisher.pl' => [qw(publish_assets publish_media preview_story preview_media)],
    );
    my $script = basename($ENV{REDIRECT_SCRIPT_NAME});
    my $rm = CGI->new($ENV{REDIRECT_QUERY_STRING})->param('rm') || '';

    return 1 if $progress_screens{$script} && first { $rm eq $_ } @{$progress_screens{$script}};
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
