=head1 NAME

Krang::Schedule::Action - Abstract class for scheduler action type classes.

=cut

package Krang::Schedule::Action;

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Schedule';

use strict;
use warnings;

=head1 SYNOPSIS

Abstract class for scheduler action types.

=head1 DESCRIPTION

Abstract class, serves as a template for action classes.

=head1 INTERFACE

action classes need to inherit from this class 
ex. use Krang::ClassLoader base => 'Schedule::Action'
and the derived class must at a minimum implement method sub execute().

=over

=item sub execute() must be redefined in derived class.

=cut

sub execute {
    my $self = shift;
    my $msg = sprintf("%s->execute(): unknown action '%s'", __PACKAGE__, $self->{action});
    $msg .= "\nmust define execute() in subclass of Schedule::Action\n";
        die($msg);
}

=back

=cut


1;

