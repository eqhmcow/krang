package Krang::CGI::Help;
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

use base 'Krang::CGI';
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile catdir);
use Krang::HTMLTemplate;

sub setup {
    my $self = shift;
    $self->start_mode('show');
    $self->run_modes(show => \&show);
}

sub show {
    my $self = shift;
    my $query = $self->query;
    my $topic = $query->param('topic') or die "Missing required topic.";
    die "Bad topic." if $topic !~ /^\w+/;

    # find topic help file
    my $file = catfile(KrangRoot, 'htdocs', 'help', "$topic.html");
    if (not -e $file) { 
        return "<h2>Unable to find help file for '$topic' topic.</h2>";
    }

    # load as template to process includes
    my $template = Krang::HTMLTemplate->new(filename => $file,
                                            path     => ['Help'],
                                            search_path_on_includes => 1,
                                            cache    => 1);

    return $template->output;
}

1;
