package Krang::CGI;
use strict;
use warnings;

=head1 NAME

Krang::CGI - Krang base class for CGI modules

=head1 SYNOPSIS

  package Krang::CGI::SomeSuch;
  use base 'Krang::CGI';

  sub setup {
    my $self = shift;
    $self->start_mode('status');
    $self->run_modes(status => \&status);
  }

  sub status {
    my $self = shift;
    my $query = $self->query;
    # ...
  }

=head1 DESCRIPTION

Krang::CGI is a subclass of L<CGI::Application>.  All the usual
CGI::Application features are available.  

=head1 INTERFACE

See L<CGI::Application>.

=cut

use base 'CGI::Application';
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catdir rel2abs);

use Krang::CGI::Status;
use Krang::CGI::ElementEditor;
use Krang::CGI::Login;

# setup tmpl_path
sub new {
    my $pkg = shift;
    my $self = $pkg->SUPER::new(@_);
    $self->tmpl_path(rel2abs(catdir(KrangRoot, "templates")) . "/");
    return $self;
}

sub load_tmpl {
    my $pkg = shift;
    return $pkg->SUPER::load_tmpl(@_, cache => 1);
}
1;
