package Krang::Desk;
use strict;
use warnings;

use Carp qw(croak);
use Krang::DB qw(dbh);

=head1 NAME

Krang::Desk - Krang Desk API

=head1 SYNOPSIS

    use Krang::Desk;

    # add a new desk, defaulting to next available slot in order
    my $desk = Krang::Desk->new( name => 'Publish');

    # return desk id
    my $desk_id = $desk->desk_id;
    
    # return desk order
    my $desk_order = $desk->order;

    # create another desk, this time choosing order of
    # another desk, effectively making order of other
    # desk + 1
    my $desk2 = Krang::Desk->new( name => 'Print', order => $desk->order );

    # return desk objects with name 'Publish'
    my @desks = Krang::Desk->find( name => 'Publish' );

    # reorder desks (in this case switch order of the two we have created)
    Krang::Desk->reorder(   $desk[0]->desk_id => $desk2->order,
                            $desk2->desk_id => $desk[0]->order );
    
    $desk->delete();
     
=head1 DESCRIPTION

Krang::Desk provides methods to create, delete, find and reorder desks.

=head1 INTERFACE

=head2 METHODS

=over

=item new()

Add a new desk and save it.  Takes the following parameters.

=over 4

=item name 

name of desk (required)

=item order

position in order of desks for this desk. defaults to next
available slot in desk order.

=back

=cut
use Krang::MethodMaker
    new_with_init => 'new',
    new_hash_init => 'hash_init',
    get_set       => [ qw( name ord ) ],
    get => [ qw( desk_id ) ];

sub init {
    my $self = shift;
    my %args = @_;
    croak(__PACKAGE__."->new - 'name' is a required parameter") if not $args{'name'};

    # finish the object
    $self->hash_init(%args);

    # insert record into db
    $self->_insert(%args);

    return $self;
}

sub _insert {
    my $self = shift;
    my %args = @_;
    my $dbh = dbh();

    # figure out how many desks there currently are
    my $sth = $dbh->prepare('SELECT count(*) from desk');
    $sth->execute();
    my $count;
    $count = $sth->fetchrow_array;
    $sth->finish;

    if ($args{order}) {
        if ($count >= $args{order}) {
            $sth = $dbh->prepare('UPDATE desk set ord = (ord + 1) where ord >= ?');
            $sth->execute($args{order});
            $sth->finish;
        } elsif (($count + 1) < $args{order}) {
            $args{order} = $count + 1;
        }
    } else {
        $args{order} = $count + 1; 
    }
   
    $sth = $dbh->prepare('INSERT INTO desk (name, ord) values (?,?)');
    $sth->execute($args{'name'}, $args{order});
    $sth->finish;

    $self->{desk_id} = $dbh->{mysql_insertid}; 
    $self->{name} = $args{name};
    $self->{ord} = $args{order};

}

=item desk_id()

Return desk id for desk object.

=item name()

Return desk name

=item order()

Return desk order. Please note that if desk order is shuffled in
the database, you will have to reload the desk object to get an
accurate order.

=cut

sub order {
    my $self = shift;
    return $self->{ord};
}

=item reorder()

Reorder desks as specified.  Takes hash of desk_id => order pairs.

=cut

sub reorder {
    my $self = shift;
    my %args = @_;
    my $dbh = dbh();

    foreach my $desk_id (keys %args) {
        $dbh->do('UPDATE desk set ord = ? where desk_id = ?', undef, $args{$desk_id}, $desk_id); 
    }
}

=item find()

Returns a list of desk objects, desk_ids, or count based on search 
parameters. Valid params below:

=over 4

=item * name

=item * order

=item * desk_id

=item * count

If this argument is specified, the method will return a count of 
the desks matching criteria.

=item * ids_only

Returns only desk_ids for the results found in the DB, not objects.

=item * order_by

Specify the field by means of which the results will be sorted.
Defaults to 'order'.

=item * order_desc

If this is set to true, results will be sorted as descending 
(default is ascending).

=cut

sub find {
    my $self = shift;
    my %args = @_;

    my %valid_params = (    name => 1,
                            order => 1,
                            desk_id => 1,
                            count => 1,
                            ids_only => 1,
                            order_by => 1,
                            order_desc => 1
                        );

    # check for invalid params and croak if one is found
    foreach my $param (keys %args) {
        croak (__PACKAGE__."->find() - Invalid parameter '$param' called.") if not $valid_params{$param};
    }

    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.") if ($args{count} && $args{ids_only});

    my $order_by = $args{order_by} || 'ord';
    $order_by = 'ord' if ($order_by eq 'order');

    my $order_dir = $args{order_desc} ? 'desc' : 'asc';

    my $select;

    # build select part of query
    if ($args{count}) {
        $select = 'select count(*)';
    } elsif ($args{ids_only}) {
        $select = 'select desk_id';
    } else {
        $select = 'select desk_id, name, ord';
    }

    my $where_clause;
    my @where;
    if ($args{desk_id}) {
        $where_clause = "where desk_id = ?";
        push @where, $args{desk_id};
    }

    if ($args{name}) {
        $where_clause ? ($where_clause .= " and name = ?") : ($where_clause = "where name = ?");
        push @where, $args{name};
    }

    if ($args{order}) {
        $where_clause ? ($where_clause .= " and ord = ?") : ($where_clause = "where ord = ?");
        push @where, $args{order};
    }

    my $query = "$select from desk $where_clause";
    $query .= " order by $order_by $order_dir";

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(@where) || croak("Unable to execute statement $query");

    my @desk_object;

    while (my $row = $sth->fetchrow_hashref()) {
        my $obj;
        if ($args{'count'}) {
            return $row->{count};
        } elsif ($args{'only_ids'}) {
            $obj = $row->{media_id};
        } else {
            $obj = bless {%$row}, $self;
        }
        push (@desk_object,$obj);
    }
    $sth->finish();
    return @desk_object;
 
}

=item delete()

Delete a desk. Takes a desk_id as argument if called as class method.

=cut

sub delete {
    my $self = shift;
    my $desk_id = shift;
    my $dbh = dbh;

    my $is_object = $desk_id ? 0 : 1;
    $desk_id = $self->{desk_id} if not $desk_id;
    croak(__PACKAGE__."->delete - No desk_id specified.") if not $desk_id; 

    my $order;

    # find order if this is not object
    if ($is_object) {
        $order = $self->{ord};
    } else {
        my $sth = $dbh->prepare('SELECT ord from desk where desk_id = ?');
        $sth->execute($desk_id);
        $order = $sth->selectrow_array;
        $sth->finish;
    }
   
    # drop down the order of any desks higher than this one 
    my $sth = $dbh->prepare('UPDATE desk set ord = (ord - 1) where ord > ?');
    $sth->execute($order);
    $sth->finish;

    # fianlly, delete the desk
    $sth = $dbh->prepare('DELETE from desk where desk_id = ?');
    $sth->execute($desk_id);
    $sth->finish;
}

=back

=cut

1;

