package Krang::ListGroup;
use strict;
use warnings;
use Krang::DB qw(dbh);
use Krang::Session qw(%session);
use Krang::Log qw( debug info );
use Krang::User;
use Carp qw(croak);

# constants 

use constant RO_FIELDS => qw( list_group_id );
use constant RW_FIELDS => qw( name description );

=head1 NAME

    Krang::ListGroup -  interface to manage list groups.

=head1 SYNOPSIS

    use Krang::ListGroup;

    my $group = Krang::ListGroup->new(  name => 'testlistgroup',
                                        description => 'desc here' );

    $group->save;

    my @groups_found = Krang::ListGroup->find( name => 'testlistgroup' );

    $group->delete;
    
=head1 DESCRIPTION

This class handles the management of list groups.

=head1 INTERFACE

=head2 METHODS

=over 

=item new()

Creates list_group object.

=over

=item * 

name

=item *

description

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

Saves (inserts) list group to the database, or updates if it already exists.

=cut

sub save {
    my $self = shift;
    my $dbh = dbh;
    my $list_group_id;

    # if this is not a new list group
    if (defined $self->{list_group_id}) {
        $list_group_id = $self->{list_group_id};
        
        # get rid of list_group_id 
        my @save_fields = grep {$_ ne 'list_group_id'} RO_FIELDS,RW_FIELDS;

        my $sql = 'UPDATE list_group set '.join(', ',map { "$_ = ?" } @save_fields).' WHERE list_group_id = = ?';
        $dbh->do($sql, undef, (map { $self->{$_} } @save_fields),$list_group_id);

    } else {
        my @save_fields =  (RO_FIELDS,RW_FIELDS);
        my $sql = 'INSERT INTO list_group ('.join(',', @save_fields).') VALUES (?'.",?" x ((scalar @save_fields) - 1).")";
        debug(__PACKAGE__."->save() - $sql");
        
        $dbh->do($sql, undef, map { $self->{$_} } @save_fields);
        
        $self->{list_group_id} = $dbh->{mysql_insertid};
    }
}

=item find()

Find and return list groups with parameters specified.

Supported keys:

=over 4

=item *

list_group_id

=item *

name

=item *

name_like 

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
    my @lg_object;

    my %valid_params = ( list_group_id => 1,
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
        if ( ($key eq 'name') || ($key eq 'list_group_id') ) {   
            push @where, $key;
        }
    }

    my $where_string = join ' and ', (map { "$_ = ? " } @where);
    
    if ($args{name_like}) {
        $where_string = $where_string ? ' and name like ? ' : ' name like ?';
        push (@where, 'name_like');
    }

    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*) as count';
    } elsif ($args{'ids_only'}) {
        $select_string = 'list_group_id';
    } else {
        $select_string = join(',', (RO_FIELDS,RW_FIELDS));
    }

    my $sql = "select $select_string from list_group";
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
            $obj = $row->{list_group_id};
            push (@lg_object,$obj);
        } else {
            $obj = bless {%$row}, $self;

            push (@lg_object,$obj);
        }
    }
    $sth->finish();
    return @lg_object;

}

=item delete()

Delete list group specified.

=cut

sub delete {
    my $self = shift;
    my $list_group_id = shift;
    my $dbh = dbh;                                                                             
    my $is_object = $list_group_id ? 0 : 1;

    $list_group_id = $self->{list_group_id} if $is_object;

    $dbh->do('DELETE from list_group where list_group_id = ?', undef, $list_group_id);
    
}

=back 

=cut

1;
 
