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
    
    # add new alert scenario - user 1 will be notified when any new stary is 
    # created in category 3 (or its decendants)
    my $alert = Krang::Alert->new(  user_id => '1',
                                    action => 'new',
                                    category_id => '3' ); 

    # save the alert
    $alert->save;

    # add new alert scenario - user 1 will be notified when any story is
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
    # This is a convenience method that sues Krang::Alert->find() 
    # and Krang::Schedule->new()
    Krang::Alert->check_alert(  history_object => $history_object,  
                                story_object => $story_object );
    
    # delete alert scenario
    $alert->delete();

=head1 DESCRIPTION

This class handles the storage of Krang::Story events to alert upon. It also checks Krang::History objects to see if an alert is matched.  If so, an alert mailing ( Krang::Alert->send() ) will be scheduled in Krang::Schedule. 

=head1 INTERFACE

=head2 METHODS

=over 

=item new()

This adds a new scenario to alert upon.  

Supports the following name-value pairs:

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

=item save()

Saves (inserts) alert scenario to the database, or updates scenario if already exists.

=cut

sub save {
    my $self = shift;
    my $dbh = dbh;
    my $alert_id;

    # if this is not a new alert
    if (defined $self->{alert_id}) {
        $alert_id = $self->{alert_id};
        
        # get rid of alert_id 
        my @save_fields = grep {$_ ne 'alert_id'} FIELDS;

        my $sql = 'UPDATE alert set '.join(', ',map { "$_ = ?" } @save_fields).' WHERE alert_id = = ?';
        $dbh->do($sql, undef, (map { $self->{$_} } @save_fields),$alert_id);

    } else {
        $dbh->do('INSERT INTO media ('.join(',', FIELDS).') VALUES (?'.",?" x (scalar FIELDS - 1).")", undef, map { $self->{$_} } FIELDS);
        
        $self->{alert_id} = $dbh->{mysql_insertid};
    }
}

=item find()

Find and return alert objects with parameters specified.

Supported keys:

=over 4

=item *

alert_id

=item *

user_id

=item *

action

=item *

desk_id

=item *

category_id - will traverse the tree looking and also look for parent categories. an array of category ids can be passed in as well.

=item *

order_by - field to order search by, defaults to alert_id

=item *

order_desc - results will be in ascending order unless this is set to 1 (making them descending).

=item *

limit - limits result to number passed in here, else no limit.

=item *

offset - offset results by this number, else no offset.

=item *

count - return only a count if this is set to true.

=item *

only_ids - return only alert_ids, not objects if this is set true.

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my $dbh = dbh;

    my @where;
    my @alert_object;

    # set defaults if need be
    my $order_by =  $args{'order_by'} ? $args{'order_by'} : 'alert_id';
    my $order_desc = $args{'order_desc'} ? 'desc' : 'asc';
    my $limit = $args{'limit'} ? $args{'limit'} : undef;
    my $offset = $args{'offset'} ? $args{'offset'} : 0;
    
    # set simple keys
    foreach my $key (keys %args) {
        if ( ($key eq 'alert_id') || ($key eq 'user_id') || ($key eq 'action') || ($key eq 'desk_id') ) {   
            push @where, $key;
        }
    }

    my $where_string = join ' and ', (map { "$_ = ?" } @where);

    if ($args{'category_id'}) {
        if (ref($args{'category_id'}) eq 'ARRAY') {
            my @all_cats;
            my @cats = {$args{'category_id'}};
            foreach my $cat ( @cats ) {
                my @ancestors = $cat->ancestors( $cat );
                push @all_cats, @ancestors;
            }

            push @all_cats, @cats;

            $where_string ? ($where_string .= 'AND '.(join ' OR ', (map { "category_id = $_"} @all_cats))) : ($where_string = (join ' OR ', (map { "category_id = $_"} @all_cats)));
        } else {
            $where_string ? ($where_string .= 'AND category_id = '.$args{'category_id'}) : ($where_string = 'category_id = '.$args{'category_id'});
        }
    }

    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*)';
    } elsif ($args{'only_ids'}) {
        $select_string = 'alert_id';
    } else {
        $select_string = join(',', FIELDS);
    }

    my $sql = "select $select_string from alert";
    $sql .= " where ".$where_string if $where_string;
    $sql .= " order by $order_by $order_desc";

    # add limit and/or offset if defined 
    if ($limit) {
       $sql .= " limit $offset, $limit";
    } elsif ($offset) {
        $sql .= " limit $offset, -1";
    }

    my $sth = $dbh->prepare($sql);
    $sth->execute(map { $args{$_} } @where) || croak("Unable to execute statement $sql");

    while (my $row = $sth->fetchrow_hashref()) {
        my $obj;
        if ($args{'count'}) {
            return $row->{count};
        } elsif ($args{'only_ids'}) {
            $obj = $row->{alert_id};
        } else {
            $obj = bless {%$row}, $self;

            push (@alert_object,$obj);
        }
    }
    $sth->finish();
    return @alert_object;

}

=item check_alert()

This method takes two arguments, a Krang::History object and a Krang::Story object. 

=cut 

sub check_alert {
    my $self = shift;
    my %args = @_;

    my $history = $args{history};
    my $story = $args{story};

    my @cat_objects = $story->categories;
    my @category_ids = [ map { $_->category_id } @cat_objects];

    croak(__PACKAGE__."->check_alert requires a valid Krang::History object.") if (ref $history ne 'Krang::History');

    croak(__PACKAGE__."->check_alert requires a valid Krang::Story object.") if (ref $history ne 'Krang::Story');
 
    my @matched_alerts = Krang::Alert->find( only_ids => 1, action => $history->action, category_id => @category_ids );  

    foreach my $alert_id ( @matched_alerts ) {
        my $schedule = Krang::Schedule->new(    object_type => 'alert',
                                                object_id => $alert_id,
                                                action => 'send',
                                                date => localtime,
                                                repeat      => 'never',
                                                context     => [ user_id => $history->user_id ]
                                            );   
        $schedule->save(); 
    }
}

=back 

=cut

1;
 
