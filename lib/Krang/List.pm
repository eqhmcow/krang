package Krang::List;
use strict;
use warnings;
use Krang::DB qw(dbh);
use Krang::Session qw(%session);
use Krang::Log qw( debug info );
use Krang::User;
use Carp qw(croak);

# constants 

use constant RO_FIELDS => qw( list_id );
use constant RW_FIELDS => qw( name list_group_id parent_list_id );

=head1 NAME

    Krang::List -  interface to manage lists.

=head1 SYNOPSIS

    use Krang::List;

    # create and save new list in Krang::ListGroup 2
    my $list = Krang::List->new(    name => 'list1',
                                    list_group_id => 2,
                                );

    $list->save();
   
    # create new list in same group with first list as parent 
    my $list2 = Krang::List->new(   name => 'list2',
                                    list_group_id => 2,
                                    parent_list_id => $list->list_id );

    $list2->save();

    # find and return lists in Krang;:ListGroup 2
    my @found = Krang::List->find( list_group_id => 2 );

    # delete them both
    $list->delete;
    $list2->delete;
                                
=head1 DESCRIPTION

This class handles management of krang lists. Each list must be a 
member of a Krang::ListGroup, and may optionally have another 
Krang::List as a parent.  

The actual contents of a list is handles by Krang::ListItem.

Currently, krang lists should only be 
created via load on database make as configured in an ElementSet's
lists.conf file.

=head1 INTERFACE

=head2 METHODS

=over 

=item new()

Creates list object.

=over

=item * 

name

=item *

list_group_id

=item *

parent_list_id

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

    # finish the object
    $self->hash_init(%args);

    return $self;
}

=item save()

Saves (inserts) list into the database, or updates if it already exists.

=cut

sub save {
    my $self = shift;
    my $dbh = dbh;
    my $list_id;

    # if this is not a new list group
    if (defined $self->{list_id}) {
        $list_id = $self->{list_id};
        
        # get rid of alert_id 
        my @save_fields = grep {$_ ne 'list_id'} RO_FIELDS,RW_FIELDS;

        my $sql = 'UPDATE list_group set '.join(', ',map { "$_ = ?" } @save_fields).' WHERE list_id = = ?';
        $dbh->do($sql, undef, (map { $self->{$_} } @save_fields),$list_id);

    } else {
        my @save_fields =  (RO_FIELDS,RW_FIELDS);
        my $sql = 'INSERT INTO list_group ('.join(',', @save_fields).') VALUES (?'.",?" x ((scalar @save_fields) - 1).")";
        debug(__PACKAGE__."->save() - $sql");
        
        $dbh->do($sql, undef, map { $self->{$_} } @save_fields);
        
        $self->{list_id} = $dbh->{mysql_insertid};
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
 
