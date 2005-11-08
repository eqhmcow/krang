package Krang::CGI::Status;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::CGI::Status - Krang status screen

=head1 SYNOPSIS

  http://krang/instance/status

=head1 DESCRIPTION

Provides the status screen for the application.

=head1 INTERFACE

None.

=cut

use Krang::ClassLoader base => 'CGI';
use CGI qw/:standard/;
use Krang::ClassLoader 'Conf';

sub setup {
    my $self = shift;
    $self->start_mode('status');
    $self->run_modes(status => 'status');
}

sub status {
    my $self = shift;
    my $output = join("\n",
                      start_html('Krang Status'),
                      h1('Krang Status'),
                      h2('Instance Settings'),
                      table({border => 1},
                            th("Directive"), th("Value"),
                            Tr(td("Instance"), td(pkg('Conf')->instance)),
                            ( map { Tr(td($_), td(pkg('Conf')->get($_))) }
                              (qw( InstanceElementSet InstanceDBName InstanceHostName ))),
                           ),
                      h2('Global Settings'),
                        table({border => 1},
                              th("Directive"), th("Value"),
                              ( map { Tr(td($_), td(pkg('Conf')->get($_))) }
                                
                                (qw( KrangRoot ElementLibrary
                                     KrangUser KrangGroup
                                   ))),
                             ));

    return $output;
}

1;
        
