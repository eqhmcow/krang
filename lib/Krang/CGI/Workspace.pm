package Krang::CGI::Workspace;
use strict;
use warnings;

=head1 NAME

Krang::CGI::Workspace - the my workspace application

=head1 SYNOPSIS

None.

=head1 DESCRIPTION

This application manages the My Workspace for Krang.

=head1 INTERFACE

None.

=cut

use Krang::Session qw(%session);
use Krang::Log qw(debug assert affirm ASSERT);

use base 'Krang::CGI';

sub setup {
    my $self = shift;
    $self->start_mode('show_workspace');
    $self->mode_param('rm');
    $self->run_modes(show_workspace         => \&show_workspace);
}

sub show_workspace {
    my $self = shift;
    my $template = $self->load_tmpl("workspace.tmpl");
    return $template->output;
}

1;
