package Krang::Alert;
use strict;
use warnings;
use Krang::DB qw(dbh);
use Krang::Session qw(%session);
use Krang::Log qw( info );
use Krang::Schedule;
use Carp qw(croak);
use Time::Piece;
use Time::Piece::MySQL;
use Mail::Sender;

# constants 
use constant FIELDS => qw( alert_id user_id action desk_id category_id );
use constant ACTIONS => qw( new save checkin checkout publish move );

=head1 NAME

    Krang::Alert -  interface to specify Krang::Story events to alert upon, 
                    schedule alerts, and mail out alerts.

=head1 SYNOPSIS

    use Krang::Alert;
    
    # add new alert - user 1 will be notified when any new stary is 
    # created in category 3 (or its decendants)
    my $alert = Krang::Alert->new(  user_id => '1',
                                    action => 'new',
                                    category_id => '3' ); 

    # save the alert
    $alert->save;

    # add new alert - user 1 will be notified when any story is
    # moved to desk 4
    my $alert2 = Krang::Alert->new( user_id => '1',
                                    action => 'move',
                                    desk_id => '4' );

    # save the alert
    $alert2->save;

    # Let's pretend that category 5 is a decendant of category 3.
    # This find should return the $alert object from the above example. 
    my @found = Krang::Alert->find( user_id => '1',
                                    action => 'new',
                                    category_id => '5' ); 

    # check to see if history event should trigger an alert
    # for specified object.  If a match is found, an alert 
    # will be scheduled to be mailed with Krang::Schedule
    # This is a convenience method for Krang::Alert->find() and 
    # Krang::Schedule->new()
    Krang::Alert->check_alert(  history_object => $history_object,  
                                story_object => $story_object );

     
=head1 DESCRIPTION

This class handles the storage of Krang::Story events to alert upon. It also checks Krang::History objects to see if an alert is matched.  If so, an alert mailing ( Krang::Alert->send() ) will be scheduled in Krang::Schedule. 

=head1 INTERFACE

=head2 METHODS

=over 

=item new()

This adds a new scenario to alert upon.  

Supports the following name-valule pairs:

=over

=item * 

user_id

=item * 

action - one of ( new save checkin checkout publish move )

=item *

category_id

=item * 

desk_id

=back

=cut

use Krang::MethodMaker
    new_with_init => 'new',
    new_hash_init => 'hash_init',
    get_set       => [ FIELDS ];

sub init {
    my $self = shift;
    my %args = @_;

    # finish the object
    $self->hash_init(%args);

        return $self;
}

=back 

=cut

1;
 
