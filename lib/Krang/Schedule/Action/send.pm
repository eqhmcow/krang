=head1 NAME

Krang::Schedule::Action::send - Scheduler Action class which implements scheduler send functions 

=cut

package Krang::Schedule::Action::send;

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Carp qw(verbose croak);
use Krang::ClassLoader base => 'Schedule::Action';
use Krang::ClassLoader Log => qw/ASSERT assert critical debug info/;
use Krang::ClassLoader 'Alert';

=head1 SYNOPSIS

Concrete Krang::Scheduler::Action class which sends scheduled alerts. 

=head1 DESCRIPTION

This class sends scheduled alerts.  It is instantiated on action type. 

=head1 INTERFACE

use Krang::ClassLoader base => 'Schedule::Action';
sub execute { }

=head1 METHODS 

=over

=item C<< $schedule->execute() >>

Action method for class.  Must be defined in Krang::Scheduler::Action classes.
This method serves as the entry point method in Krang::Scheduler::Action class implementations.
In this class it functions to send scheduled alerts.

=back

=cut

sub execute {
    my $self = shift;

    if (! $self->_object_exists()) { 
        info(sprintf("%s->execute(): Cannot run schedule id '%i'. %s id='%i' cannot be found. Deleting scheduled job.", __PACKAGE__, $self->schedule_id, $self->object_type, $self->object_id));
        $self->delete();
        return;
    }

    $self->_send();

    $self->clean_entry();
}

=over

=item C<< $schedule->_send() >>

Private method that handles the sending of a Krang::Alert.
Will throw any errors propegated by the Krang::Alert system.

=back

=cut


sub _send {
    my $self = shift;

    my $type    = $self->{object_type};
    my $id      = $self->{object_id};
    my $context = $self->{context};

    eval {
        pkg('Alert')->send(alert_id => $id, @$context);
    };

    if (my $err = $@) {
        # log the error
        my $msg = __PACKAGE__ . "->_send(): Attempt to send alert failed: $err";
        die $msg;
    }
}

=head1 See Also

=over

=item Krang::Scheduler

=item Krang::Scheduler::Action

=back

=cut

1;
