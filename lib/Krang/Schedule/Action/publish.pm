=head1 NAME

Krang::Schedule::Action::publish - Scheduler Action class which implements scheduler publish
 functions 

=cut

package Krang::Schedule::Action::publish;

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'Schedule::Action';
use Krang::ClassLoader Log => qw/ASSERT assert critical debug info/;
use Krang::ClassLoader 'Media';
use Krang::ClassLoader 'Publisher';
use Krang::ClassLoader 'Story';
use Carp qw(verbose croak);


=head1 SYNOPSIS

Concrete Krang::Scheduler::Action class which publishes media and stories object types 

=head1 DESCRIPTION

This class publishes scheduled stories and media.

=head1 INTERFACE

use Krang::ClassLoader base => 'Schedule::Action';
sub execute { }

=head1 METHODS 

=over

=item C<< $schedule->execute() >>

Action method for class.  Must be defined in Krang::Scheduler::Action classes.
This method serves as the entry point method in Krang::Scheduler::Action class implementations.
In this class it functions to publish stories and media type objects.

=back

=cut

sub execute {
    my $self = shift;

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

    $self->_publish();

    if ($self->{repeat} eq 'never') {
        # never to be run again.  delete yourself.
        $self->delete();
    } else {
        # set last_run, update next_run, save.
        $self->{last_run} = $self->{next_run};
        $self->{next_run} = $self->_calc_next_run(skip_match => 1);
        $self->save();
    }
}

=over

=item C<< $schedule->_publish() >>

Takes the story or media object pointed to, and attempts to publish it.

Will return if successful.  It is assumed that failures in the publish process will
cause things to croak() or die().  If trapped, a Schedule-log entry will be made,
and the error will be propegated further.

=back

=cut

sub _publish {
    my $self = shift;

    my $publisher = pkg('Publisher')->new();

    my $object = $self->{object};
    my $err;

    if ($object->isa( pkg('Media') )) {
        eval {
            $publisher->publish_media(media => $object);
        };

        if ($err = $@) {
            my $msg = sprintf("%s->_publish(): error publishing Media ID=%i: %s",
                              __PACKAGE__, $object->media_id, $err);
            die $msg;
        }
    } elsif ($object->isa( pkg('Story') )) {
        # check to make sure scheduled publish isn't disabled
        unless ($object->element->publish_check) {
            debug(sprintf("%s->_publish(): Story id '%i' has scheduled publish disabled.  Skipping.",
                          __PACKAGE__, $object->story_id()));
            return;
        }

        eval {
            $publisher->publish_story(story => $object, version_check => 0);
        };

        if (my $err = $@) {
            my $msg = sprintf("%s->_publish(): error publishing Story ID=%i: ERR=%s",
                              __PACKAGE__, $object->story_id, (ref $err ? ref $err : $err));
            die $msg;
        }
    }
}

=head1 See Also

=over

=item Krang::Scheduler

=item Krang::Scheduler::Action

=back

=cut

1;
