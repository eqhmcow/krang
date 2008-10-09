package Krang::CGI::Help;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::CGI::Help - Krang help screens

=head1 SYNOPSIS

  http://krang/help?topic=workspace

=head1 DESCRIPTION

Provides help screens given a topic.

=head1 INTERFACE

None.

=cut

use Krang::ClassLoader base => 'CGI';
use Krang::ClassLoader Conf => qw(KrangRoot DefaultLanguage);
use File::Spec::Functions qw(catfile catdir);
use Krang::ClassLoader 'HTMLTemplate';
use Krang::ClassLoader 'File';
use Krang::ClassLoader Session => qw(%session);

sub setup {
    my $self = shift;
    $self->start_mode('show');
    $self->run_modes(show => 'show');
}

sub show {
    my $self  = shift;
    my $query = $self->query;
    my $topic = $query->param('topic') or die "Missing required topic.";
    die "Bad topic." if $topic !~ /^\w+/;

    # maybe localized help
    my $lang = $session{language} || DefaultLanguage || 'en';
    my $symlink = catdir(KrangRoot, 'htdocs', 'help', $lang);
    my $localized_help_dir = -l $symlink ? $lang : '';

    # find topic help file
    my $file = pkg('File')->find(catfile('htdocs', 'help', $localized_help_dir, "$topic.html"));
    if (not -e $file) {
        return "<h2>Unable to find help file for '$topic' topic.</h2>";
    }

    # load as template to process includes
    my $template = $self->load_tmpl(
        $file,
        path                   => ['Help'],
        search_path_on_include => 1,
        cache                  => 1
    );

    return $template->output;
}

1;
