=head1 NAME

Krang::Schedule::Action::expire - Scheduler Action class which implements scheduler expire functions

=cut

package Krang::Schedule::Action::expire;

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'Schedule::Action';
use Krang::ClassLoader Log => qw(ASSERT assert critical debug info);
use Carp qw(verbose croak);

=head1 SYNOPSIS

Concrete Krang::Scheduler::Action class which deletes AKA expires media and stories 

=head1 DESCRIPTION

This class deletes stories and media.  It is instantiated in the scheduler depending on action type. 

=head1 INTERFACE

use Krang::ClassLoader base => 'Schedule::Action';
sub execute { }

=head1 METHODS 

=over

=item C<< $schedule->execute() >>

Action method for class.  Must be defined in Krang::Scheduler::Action classes.
This method serves as the entry point method in Krang::Scheduler::Action class implementations.
In this class it functions to delete (expire) media and stories.

=back

=cut

sub execute {
    my $self = shift;

    ## side effect of stuffing {object} in _object_exists()
    if ($self->_object_exists()) {
        if ($self->_object_checked_out()) {
            info(sprintf("%s->execute(): Cannot run Schedule id '%i'.  %s id='%i' is checked out.",
                __PACKAGE__, $self->schedule_id, $self->object_type, $self->object_id));
            return;
        }
    } else {
        info(sprintf("%s->execute(): Cannot run schedule id '%i'. %s id='%i' cannot be found. Deleting scheduled job.", __PACKAGE__, $self->schedule_id, $self->object_type, $self->object_id));
        $self->delete();
        return;
    }

    $self->_expire();

    $self->clean_entry();
}

=over

=item  C<< $schedule->_expire() >>

Runs an expiration job on object_type-object_id.

Will throw a croak() if it cannot find the appropriate object, or
will propegate errors thrown by the object itself.

=back

=cut

sub _expire {

    my $self = shift;
    my $obj = $self->{object};

    $obj->trash();
    debug(sprintf("%s->_expire(): Deleted %s id '%i'.",
                 __PACKAGE__, $self->{object_type}, $self->{object_id}));

}

=head1 See Also

=over

=item Krang::Scheduler

=item Krang::Scheduler::Action

=back

=cut

1;
