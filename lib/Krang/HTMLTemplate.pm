package Krang::HTMLTemplate;
use strict;
use warnings;

=head1 NAME

Krang::HTMLTemplate - HTML::Template wrapper for Krang

=head1 SYNOPSIS

None.  See L<HTML::Template>.

=head1 DESCRIPTION

This module is a wrapper around HTML::Template which sets up certain
automatic template variables for templates loading through
Krang::CGI::load_tmpl().  Specifically, it is responsible for all
variables and loops found in F<header.tmpl>.

=head1 INTERFACE

See L<HTML::Template>.

=cut

use base 'HTML::Template';
use Krang::Session qw(%session);
use Krang::Conf qw(InstanceDisplayName KrangRoot);
use Krang::Message qw(get_messages clear_messages);
use Krang::Desk;
use File::Spec::Functions qw(catdir);

# overload output() to setup template variables
sub output {
    my $template = shift;

    my @desks = Krang::Desk->find();
    my @header_desk_loop;
    
    if ($template->query(name => 'header_desk_loop')) { 
        foreach my $desk (@desks) {
            push (@header_desk_loop, { desk_id => $desk->desk_id, desk_name => $desk->name
});
        }
        $template->param( header_desk_loop => \@header_desk_loop );
    }

    # fill in header variables as necessary
    if ($template->query(name => 'header_user_name')) {
        my ($user) = Krang::User->find(user_id => $ENV{REMOTE_USER});
        $template->param(header_user_name => $user->first_name . " " . 
                                             $user->last_name) if $user;
    }
    
    $template->param(header_instance_name => InstanceDisplayName)
      if $template->query(name => 'header_instance_name');


    if ($template->query(name => 'header_message_loop')) {
        $template->param(header_message_loop => 
                         [ map { { message => $_ } } get_messages() ]);
        clear_messages();
    }
                                                 
    return $template->SUPER::output();
}

1;

