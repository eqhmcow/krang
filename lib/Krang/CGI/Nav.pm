package Krang::CGI::Nav;
use strict;
use warnings;

=head1 NAME

Krang::CGI::Nav - the nav bar application 

=head1 SYNOPSIS

Called from within F<templates/header.tmpl>:

  <iframe id="nav" height="100%" width="150" align="left" frameborder="0"
          hspace="0" vspace="0" marginheight="0" marginwidth="0"
          scrolling="no" style="overflow:visible" src="nav.pl">
  </iframe>

=head1 DESCRIPTION

This application manages the nav bar for Krang.  It determines which
options the user should see and displays them in a list.

=head1 INTERFACE

None.

=cut

use Krang::Session qw(%session);
use Krang::Log qw(debug assert affirm ASSERT);

use base 'Krang::CGI';

sub setup {
    my $self = shift;
    $self->start_mode('show_nav');
    $self->mode_param('nav_rm');
    $self->run_modes(show_nav         => \&show_nav);
}

sub show_nav {
    my $self = shift;
    my $template = $self->load_tmpl("nav.tmpl");
    return $template->output;
}

1;
