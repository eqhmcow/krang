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

# Load Krang to set instance
use Krang;

use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catdir rel2abs);

use Krang::CGI::Status;
use Krang::CGI::ElementEditor;
use Krang::CGI::Login;
use Krang::Log qw(critical info debug);


# Krang sessions
use Krang::Session qw/%session/;


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


sub run {
    my $self = shift;
    my @args = ( @_ );

    # Load and unload session ONLY if we have a session ID set
    my $we_loaded_session = 0;
    if (my $session_id = $ENV{KRANG_SESSION_ID}) {
        # Load session if we're in CGI_MODE and we have a KRANG_SESSION_ID
        debug("Krang::CGI:  Loading Session '$session_id'");
        Krang::Session->load($session_id);
        $we_loaded_session++;
    }


    #
    # Run CGI -- catch exception if we have one, save it for after session un-load
    #
    my $output = '';
    eval {   $output = $self->SUPER::run(@args)   };
    my $cgiapp_errors = $@;


    # Unload session if we loaded it
    if ($we_loaded_session) {
        debug("Krang::CGI:  UN-Loading Session");
        Krang::Session->unload();
    }

    die ("Krang::CGI caught exception: $cgiapp_errors") if ($cgiapp_errors);

    return $output;
}


# Krang-specific dump_html
sub dump_html {
    my $self = shift;
    my $output = '';

    # Dump Session state
    $output .= "<P>\nSession State:<BR>\n<OL>\n";
    foreach my $ek (sort(keys(%session))) {
        $output .= "<LI> $ek => '<B>".$session{$ek}."</B>'\n";
    }
    $output .= "</OL>\n";

    # Dump Params
    $output .= "<P>\nQuery Parameters:<BR>\n<OL>\n";
    my @params = $self->query->param();
    foreach my $p (sort(@params)) {
        my @data = $self->query->param($p);
        my $data_str = "'<B>".join("</B>', '<B>", @data)."</B>'";
        $output .= "<LI> $p => $data_str\n";
    }
    $output .= "</OL>\n";

    # Dump ENV
    $output .= "<P>\nQuery Environment:<BR>\n<OL>\n";
    foreach my $ek (sort(keys(%ENV))) {
        $output .= "<LI> $ek => '<B>".$ENV{$ek}."</B>'\n";
    }
    $output .= "</OL>\n";

    return $output;
}


1;
