package Krang::CGI::Nav;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'CGI';
use Krang::ClassLoader Conf => qw(KrangRoot);
use File::Spec::Functions qw(catfile);
use Krang;
use Krang::ClassLoader 'AddOn';
use Krang::ClassLoader Session => qw(%session);

=head1 NAME

Krang::CGI::About - show the Nav bar

=head1 SYNOPSIS

  use Krang::ClassLoader 'CGI::Nav';
  pkg('CGI::Nav')->new()->run();

=head1 DESCRIPTION

Simply returns the HTML structure for Krang's navigation. This
is normally not needed unless an AJAX request is made which could
alter the User's navigation (ie, a desk was added or a permission
level changed).

=head1 INTERFACE

=head2 RUN MODES

=over

=cut

sub setup {
    my $self = shift;
    $self->mode_param('rm');
    $self->start_mode('show');
    $self->run_modes(show => 'show');
}

=item show

The only available run-mode, displays the navigation menu.

=cut

sub show {
    my $self = shift;
    my $template = $self->load_tmpl('nav.tmpl', path => [$session{language} || '']);
    pkg('Navigation')->fill_template(template => $template, force_ajax => 1);
    return $template->output;
}

=back

=cut

1;
