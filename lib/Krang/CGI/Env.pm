package Krang::CGI::Env;
use base qw/Krang::CGI/;
use strict;
use warnings;


# Bring in Session hash
use Krang::Session qw(%session);



sub setup {
    my $self = shift;

    $self->start_mode('dump');
    $self->run_modes(['dump']);
}


sub dump {
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


=pod

=head1 NAME

Krang::CGI::Env - Dump running run-time CGI environment


=head1 SYNOPSIS

  use Krang::CGI::Env;
  my $env = Krang::CGI::Env->new();
  $env->run();


=head1 DESCRIPTION

This CGI module is intended exclusively for debugging
during development.  This CGI app dumps three types
of data:

  1. Krang session state
  2. Query parameters
  3. Environment variable state


=head1 INTERFACE

Krang::CGI::Env is expected to be run as a 
CGI::Application web application.


=head1 AUTHOR

Jesse Erlbaum <jesse@erlbaum.net>


=cut

