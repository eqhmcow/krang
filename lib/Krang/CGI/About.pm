package Krang::CGI::About;
use strict;
use warnings;

use base 'Krang::CGI';
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);
use Krang;
use Krang::AddOn;

=head1 NAME

Krang::CGI::About - show the About Krang screen

=head1 SYNOPSIS

  use Krang::CGI::About;
  Krang::CGI::About->new()->run();

=head1 DESCRIPTION

Shows the About Krang screen listing version numbers and credits.

=head1 INTERFACE

=head2 RUN MODES

=over

=cut

sub setup {
    my $self = shift;
    $self->mode_param('rm');
    $self->start_mode('show');    
    $self->run_modes(show => 'show');
    $self->tmpl_path('About/');
}

=item show

The only available run-mode, displays the about screen.

=cut

sub show {
    my $self = shift;
    my $template = $self->load_tmpl('about.tmpl');

    $template->param(version   => $Krang::VERSION,
                     server_ip => Krang::Conf->get('ApacheAddr')
                    );
    
    my @addons = sort { lc($a->name) cmp lc($b->name) } Krang::AddOn->find();
    $template->param(addons => [ map { { name => $_->name,
                                         version => $_->version } } @addons ])
      if @addons;
    

    return $template->output();
}

=back

=cut

1;
