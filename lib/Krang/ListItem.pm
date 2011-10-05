package Krang::ListItem;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader DB      => qw(dbh);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Log     => qw( debug info );
use Krang::ClassLoader 'List';
use Carp qw(croak);

# constants

use constant RO_FIELDS => qw( list_item_id ord );
use constant RW_FIELDS => qw( data list_id parent_list_item_id );

=head1 NAME

    pkg('ListItem') -  interface to manage items within a pkg('List').

=head1 SYNOPSIS

    use Krang::ClassLoader 'ListItem';

    # create and save new list item in a Krang::List 
    my $list_item = pkg('ListItem')->new(   list => $list_object,
                                            data => 'item data here'
                                );

    $list_item->save();

    # will return what order in the list this item is; in this case 1
    # as it is the only item currently in the list
    my $order = $list_item->order;
   
    # create new list item in same list, assigning it to order 1
    # and thus moving $list_item to order 2
    my $list_item2 = pkg('ListItem')->new(  list => $list_object,
                                            order => 1,
                                            data => 'data here' );

    $list_item2->save();

    # find and return list items in list 
    my @found = pkg('ListItem')->find( list => $list_object );

    # create new list item, a member of another Krang::List
    # and child of another list item
    my $list_item3 = pkg('ListItem')->new(  list => $list_object2,
                                            parent_list_item => $list_item,
                                            data => 'data here' );

    $list_item3->save;

   
    # find list items that are children of a given list item
    my @found = pkg('ListItem')->find( parent_list_item_id => $list_item->list_item_id );
 
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

list - L<Krang::List> object

=item *

parent_list_item (optional) - a L<Krang::ListItem> object

=item *

order (optional) - will default to the next available slot

=back

=cut

use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get                              => [RO_FIELDS],
  get_set                          => [RW_FIELDS];

sub id_meth { 'list_item_id' }

sub init {
    my $self = shift;
    my %args = @_;

    # get list_id from list object
    my $list = delete $args{list} || undef;

    croak(__PACKAGE__ . "->new - Invalid pkg('List') object.")
      unless ($list and (ref $list eq pkg('List')));

    $args{list_id} = $list->list_id;

    # get list_item_id from parent_list_item object if present
    my $parent_list_item = delete $args{parent_list_item} || undef;

    croak(__PACKAGE__ . "->new - Invalid pkg('ListItem') object.")
      if ($parent_list_item and (ref $parent_list_item ne pkg('ListItem')));

    $args{parent_list_item_id} = $parent_list_item->list_item_id if $parent_list_item;

    # convert order to ord if present
    my $ord;
    $ord = delete $args{order} if $args{order};

    # finish the object
    $self->hash_init(%args);

    $self->{ord} = $ord if $ord;

    return $self;
}

=item save()

Saves (inserts) list_item into the database, or updates if it already exists.

=cut

sub save {
    my $self = shift;
    my $dbh  = dbh;
    my $list_item_id;

    my %search_criteria =
      $self->{parent_list_item_id}
      ? (parent_list_item_id => $self->{parent_list_item_id})
      : (list_id => $self->{list_id});

    my $existing = pkg('ListItem')->find(count => 1, %search_criteria);

    # if this is not a new list item
    if (defined $self->{list_item_id}) {
        my $list_item_id = $self->{list_item_id};

        # get rid of list_item_id
        my @save_fields = grep { $_ ne 'list_item_id' } RO_FIELDS, RW_FIELDS;

        if ($self->{old_ord}) {

            # check to see if order belongs to another list item.
            # if so, swap the order
            my $sql = 'SELECT list_item_id from list_item where ord = ? and list_item_id != ?';
            $sql .=
              $self->{parent_list_item_id} ? ' and parent_list_item_id = ?' : ' and list_id = ?';
            my $sth = $dbh->prepare($sql);
            $sth->execute(
                $self->{ord},
                $self->{list_item_id},
                (
                      $self->{parent_list_item_id}
                    ? $self->{parent_list_item_id}
                    : $self->{list_id}
                )
            );

            my ($found_liid) = $sth->fetchrow_array();

            # if one is found, update it to this object's old order
            if ($found_liid) {
                my $sql = 'update list_item set ord = ? where list_item_id = ?';
                $dbh->do($sql, undef, $self->{old_ord}, $found_liid);
                $self->{old_ord} = undef;
            } else {
                croak(__PACKAGE__ . "->save - invalid order specified (" . $self->{ord} . ").");
            }
        }

        my $sql =
            'UPDATE list_item set '
          . join(', ', map { "$_ = ?" } @save_fields)
          . ' WHERE list_item_id = ?';
        $dbh->do($sql, undef, (map { $self->{$_} } @save_fields), $list_item_id);

    } else {
        my @save_fields = (RO_FIELDS, RW_FIELDS);

        if ($self->{ord}) {
            my $sql = 'UPDATE list_item set ord = ord + 1 where ord >= ?';
            $sql .=
              $self->{parent_list_item_id} ? ' and parent_list_item_id = ?' : ' and list_id = ?';
            $dbh->do(
                $sql, undef,
                $self->{ord},
                (
                      $self->{parent_list_item_id}
                    ? $self->{parent_list_item_id}
                    : $self->{list_id}
                )
            );
        } else {
            $self->{ord} = $existing + 1;
        }
        my $sql =
            'INSERT INTO list_item ('
          . join(',', @save_fields)
          . ') VALUES (?'
          . ",?" x ((scalar @save_fields) - 1) . ")";

        my @save_vals = map { $self->{$_} } @save_fields;

        $dbh->do($sql, undef, @save_vals);

        $self->{list_item_id} = $dbh->{mysql_insertid};
    }
}

sub order {
    my $self = shift;
    my $new_order = shift || undef;

    if ($new_order) {
        $self->{old_ord} = $self->{ord};
        $self->{ord}     = $new_order;
    } else {
        return $self->{ord};
    }
}

=item find()

Find and return list items with parameters specified.

Supported keys:

=over 4

=item *

list_item_id

=item *

list_id

=item *

parent_list_item_id 

=item *

no_parent

=item * 

data

=item *

order

=item * 

order_by

=item * 

order_desc 

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
    my $dbh  = dbh;

    my @where;
    my @list_item_object;

    my %valid_params = (
        list_item_id        => 1,
        list_id             => 1,
        parent_list_item_id => 1,
        data                => 1,
        order               => 1,
        order_by            => 1,
        order_desc          => 1,
        limit               => 1,
        offset              => 1,
        count               => 1,
        ids_only            => 1,
        no_parent           => 1,
    );

    # check for invalid params and croak if one is found
    foreach my $param (keys %args) {
        croak(__PACKAGE__ . "->find() - Invalid parameter '$param' called.")
          if not $valid_params{$param};
    }

    # check for invalid argument sets
    croak(  __PACKAGE__
          . "->find(): 'count' and 'ids_only' were supplied. "
          . "Only one can be present.")
      if $args{count} and $args{ids_only};

    # set defaults if need be
    my $order_by   = $args{'order_by'}   ? $args{'order_by'} : 'ord';
    my $order_desc = $args{'order_desc'} ? 'desc'            : 'asc';
    my $limit      = $args{'limit'}      ? $args{'limit'}    : undef;
    my $offset     = $args{'offset'}     ? $args{'offset'}   : 0;

    # set simple keys
    foreach my $key (keys %args) {
        if (   ($key eq 'list_item_id')
            || ($key eq 'list_id')
            || ($key eq 'parent_list_item_id')
            || ($key eq 'data')
            || ($key eq 'order'))
        {
            push @where, $key;
        }
    }

    my $where_string = join ' and ', (map { "$_ = ? " } @where),
      ($args{no_parent} ? ("parent_list_item_id IS NULL") : ());

    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*) as count';
    } elsif ($args{'ids_only'}) {
        $select_string = 'list_item_id';
    } else {
        $select_string = join(',', (RO_FIELDS, RW_FIELDS));
    }

    my $sql = "select $select_string from list_item";
    $sql .= " where " . $where_string if $where_string;
    $sql .= " order by $order_by $order_desc";

    # add limit and/or offset if defined
    if ($limit) {
        $sql .= " limit $offset, $limit";
    } elsif ($offset) {
        $sql .= " limit $offset, 18446744073709551615";
    }

    debug(__PACKAGE__ . "->find() SQL: " . $sql);
    debug(  __PACKAGE__
          . "->find() SQL ARGS: "
          . join(', ', map { defined $args{$_} ? $args{$_} : 'undef' } @where));

    my $sth = $dbh->prepare($sql);
    $sth->execute(map { $args{$_} } @where) || croak("Unable to execute statement $sql");

    while (my $row = $sth->fetchrow_hashref()) {
        my $obj;
        if ($args{'count'}) {
            return $row->{count};
        } elsif ($args{'ids_only'}) {
            $obj = $row->{list_item_id};
            push(@list_item_object, $obj);
        } else {
            $obj = bless {%$row}, $self;

            push(@list_item_object, $obj);
        }
    }
    $sth->finish();
    return @list_item_object;

}

=item delete()

Delete list item specified.

=cut

sub delete {
    my $self         = shift;
    my $list_item_id = shift;
    my $dbh          = dbh;
    my $is_object    = $list_item_id ? 0 : 1;

    $list_item_id = $self->{list_item_id} if $is_object;
    my $order;
    my $list_id;
    my $parent_list_item_id;
    if (not $is_object) {
        my $list_item = (pkg('ListItem')->find(list_item_id => $list_item_id))[0];
        $order               = $list_item->order;
        $list_id             = $list_item->list_id;
        $parent_list_item_id = $list_item->parent_list_item_id;

    } else {
        $order = $self->{ord};
    }

    $dbh->do('DELETE from list_item where list_item_id = ?', undef, $list_item_id);

    # get rid of gaps in order
    my $sql = 'UPDATE list_item set ord = (ord - 1) where ord > ? AND list_id = ?';
    $sql .= "AND parent_list_item_id = ?" if $parent_list_item_id;
    my @args = ($order, $list_id);
    push(@args, $parent_list_item_id) if $parent_list_item_id;
    $dbh->do($sql, undef, @args);

    # delete child list_items recursively
    $sql = 'SELECT list_item_id from list_item where parent_list_item_id = ?';
    my $sth = $dbh->prepare($sql);
    $sth->execute($list_item_id);
    while (my ($lid) = $sth->fetchrow_array()) {
        $self->delete($lid);
    }
    $sth->finish();

}

=item $list_item->serialize_xml(writer => $writer, set => $set)

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self,   %args) = @_;
    my ($writer, $set)  = @args{qw(writer set)};
    local $_;

    # open up <list_item> linked to schema/list_item.xsd
    $writer->startTag(
        'list_item',
        "xmlns:xsi"                     => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation" => 'list_item.xsd'
    );

    $writer->dataElement(list_item_id        => $self->list_item_id);
    $writer->dataElement(list_id             => $self->list_id);
    $writer->dataElement(data                => $self->data);
    $writer->dataElement(order               => $self->order);
    $writer->dataElement(parent_list_item_id => $self->parent_list_item_id)
      if $self->parent_list_item_id;

    # attach list
    my ($list) = pkg('List')->find(list_id => $self->list_id);
    $set->add(object => $list, from => $self);

    # attach parent list item if one exists
    if ($self->parent_list_item_id) {
        my ($parent_list_item) = pkg('ListItem')->find(list_item_id => $self->parent_list_item_id);
        $set->add(object => $parent_list_item, from => $self);
    }

    # all done
    $writer->endTag('list_item');
}

=item C<< $list_item = Krang::ListItem->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML.  See Krang::DataSet for details.

Note that currently update will not work as there is no identifying field
other than data, which can change. However, if an identical list item 
is found, it will not be replicated. 

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set, $no_update) = @args{qw(xml set no_update)};

    # parse it up
    my $data = pkg('XML')->simple(
        xml           => $xml,
        suppressempty => 1
    );

    # get list info
    my $list_id = $set->map_id(
        class => pkg('List'),
        id    => $data->{list_id}
    );

    my ($list) = pkg('List')->find(list_id => $list_id);

    # get parent list item id if one
    my $parent;
    if ($data->{parent_list_item_id}) {
        my $parent_id = $set->map_id(
            class => pkg('ListItem'),
            id    => $data->{parent_list_item_id}
        );
        $parent = (pkg('ListItem')->find(list_item_id => $parent_id))[0];
    }

    my %list_params = (data => $data->{data}, list_id => $list->list_id);

    if ($parent) {
        $list_params{parent_list_item_id} = $parent->list_item_id;
    }

    my $dupe = (pkg('ListItem')->find(%list_params))[0] || '';
    return $dupe if $dupe;

    delete $list_params{list_id};
    $list_params{list} = $list;
    $list_params{order} = $data->{order} if ($data->{order});

    if ($parent) {
        delete $list_params{parent_list_item_id};
        $list_params{parent_list_item} = $parent;
    }

    my $li = pkg('ListItem')->new(%list_params);
    $li->save;
    return $li;

}

=back 

=head1 SEE ALSO

L<Krang::List>, L<Krang::ListGroup>, L<Krang::ElementClass::ListGroup>,
HREF[The Krang Element System|element_system.html]


=cut

1;

