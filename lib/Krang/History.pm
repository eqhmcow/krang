package Krang::History;
use strict;
use warnings;
use Krang::DB qw(dbh);
use Carp qw(croak);

# constants
use constant FIELDS qw( object_type object_id action version desk user_id timestamp );
use constant OBJECT_TYPES qw( story media template user category );
use constant ACTIONS qw( new save check_in check_out publish deploy );

=head1 NAME

    Krang::History - records historical events for krang objects

=head1 SYNOPSIS

    use Krang::History qw( add_history );

    # record that a new story with story_id of 1001 was created by user 2
    add_history(    object_type => 'story', 
                    object_id => '1001', 
                    action => 'new',
                    user_id => '2' );

    # record that version 1 of story 1001 was saved by user 2
    add_history(    object_type => 'story', 
                    object_id => '1001', 
                    action => 'save',
                    user_id => '2',
                    version => '1' );

    # record that story 1001 was checked in to desk 'Publish'
    add_history(    object_type => 'story', 
                    object_id => '1001', 
                    action => 'check_in'
                    user_id => '2',
                    desk => 'Publish' );

    # record that a new user with id 3 is created by user 2
    add_history(    object_type => 'user',
                    object_id => '3',
                    action => 'new',
                    user_id => '2' );

    # record that template 100 was deployed by user 3
    add_history(    object_type => 'template',
                    object_id => '100',
                    action => 'deploy',
                    user_id => '3' );
    
    # find and return all events for story 1001
    my @events = Krang::History->find(  object_type => 'story',
                                        object_id => '1001' );

    # find and return all events preformed by user 2
    my @events = Krang::History->find(  user_id => '2' );

    # delete all history for media object 21
    Krang::History->delete( object_type => 'media',
                            object_id => '21' );

=head1 DESCRIPTION

This class handles the storage and retrieval of historical events in a Krang object's life.  Three methods exist- add_history ,find, and delete.

=head1 INTERFACE

=head2 METHODS

=over 

=item add_history()

This method adds an entry into the database of an action taken on an object

The valid trackable objects are: Krang::Story (story), Krang::Media (media), Krang::Template (template), Krang::User (user) and Krang::Category (category). These correspond to 'object_type', and 'object_id' is used to record the unique object id.  The valid actions specified by 'action') performed on an object are new, save, check_in, check_out, publish, and deploy.  

Although some combinations of object and action are not logical or possible in Krang (i.e. check_out of a user, or publish of a category), checking for valid combinations does not occur. 

In addition to tracking actions on objects, the user who performed the action is tracked by 'user_id'.  'version' can be used to track which version of a template, story, or media object was affected.  'desk' can be used to track which desk an action was performed on.  A timestamp is added to each history event, and will appear in the field 'timestamp' on objects returned from find.

=cut

use Krang::MethodMaker
    new_with_init => 'add_history',
    new_hash_init => 'hash_init',
    get_set       => FIELDS;

sub init {
    my $self = shift;
    my %args = @_;

    # finish the object
    $self->hash_init(%args);

    $self->_save();

    return $self;
}

sub _save {
    my $self = shift;
    my $dbh = dbh;

    my $time = localtime();   
    $self->{timestamp} = $time->mysql_datetime();
 
    $dbh->do('INSERT INTO history ('.join(',', FIELDS).') VALUES (?'.",?" x (scalar FIELDS - 1).")", undef, map { $self->{$_} } FIELDS);

}

=item find()

Find and return Krang::History objects with parameters specified. Supported paramter keys:

=over 4

=item *

object_type

=item *

object_id 

=item * 

user_id

=item *

order_by - field to order search by, defaults to timestamp

=item *

order_desc - results will be in ascending order unless this is set to 1 (making them descending).

=item *

limit - limits result to number passed in here, else no limit.

=item *

offset - offset results by this number, else no offset.

=item *

count - return only a count if this is set to true.

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my $dbh = dbh;

    my @where;
    my @history_object;

    # set defaults if need be
    my $order_by =  $args{'order_by'} ? $args{'order_by'} : 'timestamp';
    my $order_desc = $args{'order_desc'} ? 'desc' : 'asc';
    my $limit = $args{'limit'} ? $args{'limit'} : undef;
    my $offset = $args{'offset'} ? $args{'offset'} : 0;

    # set simple keys
    foreach my $key (keys %args) {
        if ( ($key eq 'user_id') || ($key eq 'object_type') || ($key eq 'object_id') ) {            
            push @where, $key;
        }
    }

    my $where_string = join ' and ', (map { "$_ = ?" } @where);

    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*)';
    } else {
        $select_string = join(',', FIELDS);
    }

    my $sql = "select $select_string from history";
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
        } else {
            $obj = bless {%$row}, $self;

            # make date readable
            $obj->{timestamp} = Time::Piece->from_mysql_datetime( $self->{timestamp} );

            push (@history_object,$obj);
        }
    }
    $sth->finish();
    return @history_object;
    
}

=back

=cut

1;
 
