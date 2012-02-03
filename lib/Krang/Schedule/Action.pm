
=head1 NAME

Krang::Schedule::Action - Abstract class for scheduler action type classes.

=cut

package Krang::Schedule::Action;

use strict;
use warnings;

use Time::Piece;
use Time::Piece::MySQL;

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Schedule';

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

=back

=cut

sub execute {
    my $self = shift;
    my $msg = sprintf("%s->execute(): unknown action '%s'", __PACKAGE__, $self->{action});
    $msg .= "\nmust define execute() in subclass of Schedule::Action\n";
    die($msg);
}

=over

=item sub clean_entry() method for book keeping after executing job. 

=back

=cut

sub clean_entry {
    my $self = shift;
    $self->{_clean_entry_called} = 1;

    if ($self->{repeat} eq 'never') {

        # never to be run again.  delete yourself.
        $self->delete();
    } else {    # set last_run, update next_run, save.
        $self->{last_run} = $self->{next_run};
        $self->{next_run} = $self->_calc_next_run(skip_match => 1);

        if ($self->expires) {
            my $exp  = Time::Piece->from_mysql_datetime($self->{expires});
            my $next = Time::Piece->from_mysql_datetime($self->{next_run});
            if ($exp < $next) {
                $self->delete;
            } else {
                $self->save;
            }
        } else {
            $self->save;
        }
    }
}

=over

=item sub delete() sets internal flag and calls SUPER

=back

=cut

sub delete {
    my $self = shift;
    $self->{_delete_called} = 1;
    return $self->SUPER::delete(@_);
}

=over

=item sub cleaned_or_deleted() returns true if clean_entry() or delete() was called

=back

=cut

sub cleaned_or_deleted {
    my $self = shift;
    return 1 if $self->{_clean_entry_called} || $self->{_delete_called};
    return;
}

=over

=item sub failure_subject() should return the email subject for a final-failure notification

=back

=cut

sub failure_subject {
    my ($self, $error) = @_;
    return "KRANG ALERT: Schedule " . $self->schedule_id . " failed";
}

=over

=item sub failure_message() should return the email body for a final-failure notification

=back

=cut

sub failure_message {
    my ($self, $error) = @_;
    return "Schedule "
      . $self->schedule_id
      . " has failed and you are being notified because no further attempts will be made.";
}

=over

=item sub success_subject() should return the email subject for a success notification

=back

=cut

sub success_subject {
    my $self = shift;
    return "KRANG ALERT: Schedule " . $self->schedule_id . " succeeded";
}

=over

=item sub success_message() should return the email body for a success notification

=back

=cut

sub success_message {
    my $self = shift;
    return "Schedule " . $self->schedule_id . " has succeeded";
}

1;

