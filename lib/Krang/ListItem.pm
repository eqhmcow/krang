package Krang::ListItem;
use strict;
use warnings;
use Krang::DB qw(dbh);
use Krang::Session qw(%session);
use Krang::Log qw( debug info );
use Krang::User;
use Krang::List;
use Carp qw(croak);

# constants 

use constant RO_FIELDS => qw( list_item_id ord );
use constant RW_FIELDS => qw( data list_id parent_list_item_id );

=head1 NAME

    Krang::ListItem -  interface to manage items within a Krang::List.

=head1 SYNOPSIS

    use Krang::ListItem;

    # create and save new list item in a Krang::List 
    my $list_item = Krang::ListItem->new(   list => $list_object,
                                            data => 'item data here'
                                );

    $list_item->save();

    # will return what order in the list this item is; in this case 1
    # as it is the only item currently in the list
    my $order = $list_item->order;
   
    # create new list item in same list, assigning it to order 1
    # and thus moving $list_item to order 2
    my $list_item2 = Krang::ListItem->new(  list => $list_object,
                                            order => 1,
                                            data => 'data here' );

    $list_item2->save();

    # find and return list items in list 
    my @found = Krang::ListItem->find( list => $list_object );

    # create new list item, a member of another Krang::List
    # and child of another list item
    my $list_item3 = Krang::ListItem->new(  list => $list_object2,
                                            parent_list_item => $list_item,
                                            data => 'data here' );

    $list_item3->save;

   
    # find list items that are children of a given list item
    my @found = Krang::ListItem->find( parent_list_item_id => $list_item->list_item_id );
 
    # delete them both
    $list_item->delete;
    $list_item2->delete;
                                
=head1 DESCRIPTION

This class handles management of data items within krang lists. 

=head1 INTERFACE

=head2 METHODS

=over 

=item new()

Creates list object.

=over

=item * 

data

=item *

list - Krang::List object

=item *

parent_list_item (optional) - a Krang::ListItem object

=item *

order (optional) - will default to the next available slot

=back

=cut

use Krang::MethodMaker
    new_with_init => 'new',
    new_hash_init => 'hash_init',
    get => [ RO_FIELDS ],
    get_set       => [ RW_FIELDS ];

sub init {
    my $self = shift;
    my %args = @_;

    # get list_id from list object
    my $list = delete $args{list} || undef;

    croak(__PACKAGE__."->new - Invalid Krang::List object.") unless ($list and (ref $list eq 'Krang::List'));

    $args{list_id} = $list->list_id;

    # get list_item_id from parent_list_item object if present
    my $parent_list_item = delete $args{parent_list_item} || undef;

    croak(__PACKAGE__."->new - Invalid Krang::ListItem object.") if ($parent_list_item and (ref $parent_list_item ne 'Krang::ListItem'));
    
    $args{parent_list_item_id} = $parent_list_item->list_item_id if $parent_list_item;

    # convert order to ord if present
    $args{ord} = delete $args{order} if $args{order};

    # finish the object
    $self->hash_init(%args);

    return $self;
}

=item save()

Saves (inserts) list_item into the database, or updates if it already exists.

=cut

sub save {
    my $self = shift;
    my $dbh = dbh;
    my $list_item_id;

    my $existing = Krang::ListItem->find( count => 1 );

    # if this is not a new list item
    if (defined $self->{list_item_id}) {
        $list_id = $self->{list_item_id};
        
        # get rid of list_item_id 
        my @save_fields = grep {$_ ne 'list_item_id'} RO_FIELDS,RW_FIELDS;

        if ($self->{old_ord}) {
            # check to see if order belongs to another list item.
            # if so, swap the order
            my $sth = $dbh->prepare('SELECT list_item_id from list_item where order = ? and list_item_id != ?');
            $sth->execute($self->{ord}, $self->{list_item_id});

            my ($found_liid) = $sth->fetchrow_array();
            $sth->close;
      
            # if one is found, update it to this object's old order 
            if ($found_liid) {
                my $sql =  'update list_item set ord = ? where list_item_id = ?';
                $dbh->do($sql, undef, $self->{old_ord}, $found_liid); 
                $self->{old_ord} = undef;
            } else {
                croak(__PACKAGE__."->save - invalid order specified (".$self->{ord}.").");
            }
        }
 
        my $sql = 'UPDATE list_item set '.join(', ',map { "$_ = ?" } @save_fields).' WHERE list_item_id = = ?';
        $dbh->do($sql, undef, (map { $self->{$_} } @save_fields),$list_id);

    } else {
        my @save_fields =  (RO_FIELDS,RW_FIELDS);

        if ($self->{ord} and ($self->{ord} <= $existing)) {
            my $sql = 'UPDATE list_item set ord = ord + 1 where >= ?';
            $dbh->do($sql, undef, $self->{ord}); 
        } else {
            $self->{ord} = $existing + 1;
        }
        my $sql = 'INSERT INTO list_item ('.join(',', @save_fields).') VALUES (?'.",?" x ((scalar @save_fields) - 1).")";
        debug(__PACKAGE__."->save() - $sql");
        
        $dbh->do($sql, undef, map { $self->{$_} } @save_fields);
        
        $self->{list_item_id} = $dbh->{mysql_insertid};
    }
}

sub order {
    my $self = shift;
    my $new_order = shift || undef;

    if ($new_order) {
        $self->{old_ord} = $self->{ord};
        $self->{ord} = $new_order;
    } else {
        return $self->{ord};
    } 
}

=item find()

Find and return lists with parameters specified.

Supported keys:

=over 4

=item *

list_id

=item *

name

=item *

name_like 

=item * 

list_group_id

=item * 

parent_list_id

=item * 

order_by

=item * 

order_desc 

=item * 

limit

=item *

limit

=item *

offset

=item *

count

=item *

ids_only

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my $dbh = dbh;

    my @where;
    my @alert_object;

    my %valid_params = ( list_id => 1,
                         list_group_id => 1,
                         parent_list_id => 1,
                         name => 1,
                         name_like => 1,
                         order_by => 1,
                         order_desc => 1,
                         limit => 1,
                         offset => 1,
                         count => 1,
                         ids_only => 1 );

    # check for invalid params and croak if one is found
    foreach my $param (keys %args) {
        croak (__PACKAGE__."->find() - Invalid parameter '$param' called.") if
not $valid_params{$param};
    }

    # check for invalid argument sets
    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.")
      if $args{count} and $args{ids_only};

    # set defaults if need be
    my $order_by =  $args{'order_by'} ? $args{'order_by'} : 'name';
    my $order_desc = $args{'order_desc'} ? 'desc' : 'asc';
    my $limit = $args{'limit'} ? $args{'limit'} : undef;
    my $offset = $args{'offset'} ? $args{'offset'} : 0;
    
    # set simple keys
    foreach my $key (keys %args) {
        if ( ($key eq 'name') || ($key eq 'list_id') || ($key eq 'parent_list_id') || ($key eq 'list_group_id') ) {   
            push @where, $key;
        }
    }

    my $where_string = join ' and ', (map { "$_ = ? " } @where);
    
    if ($args{name_like}) {
        $where_string = $where_string ? ' and name like ? ' : ' name like ?';
    }

    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*) as count';
    } elsif ($args{'ids_only'}) {
        $select_string = 'list_id';
    } else {
        $select_string = join(',', (RO_FIELDS,RW_FIELDS));
    }

    my $sql = "select $select_string from list";
    $sql .= " where ".$where_string if $where_string;
    $sql .= " order by $order_by $order_desc";

    # add limit and/or offset if defined 
    if ($limit) {
       $sql .= " limit $offset, $limit";
    } elsif ($offset) {
        $sql .= " limit $offset, -1";
    }

    debug(__PACKAGE__ . "->find() SQL: " . $sql);
    debug(__PACKAGE__ . "->find() SQL ARGS: " . join(', ', map { defined $args{$_} ? $args{$_} : 'undef' } @where));

    my $sth = $dbh->prepare($sql);
    $sth->execute(map { $args{$_} } @where) || croak("Unable to execute statement $sql");

    while (my $row = $sth->fetchrow_hashref()) {
        my $obj;
        if ($args{'count'}) {
            return $row->{count};
        } elsif ($args{'ids_only'}) {
            $obj = $row->{list_id};
            push (@alert_object,$obj);
        } else {
            $obj = bless {%$row}, $self;

            push (@alert_object,$obj);
        }
    }
    $sth->finish();
    return @alert_object;

}

=item delete()

Delete list specified.

=cut

sub delete {
    my $self = shift;
    my $list_id = shift;
    my $dbh = dbh;                                                                             
    my $is_object = $list_id ? 0 : 1;

    $list_id = $self->{list_id} if $is_object;

    $dbh->do('DELETE from list where list_id = ?', undef, $list_id);
    
}

=back 

=cut

1;
 
