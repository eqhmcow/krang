package Krang::List;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader DB      => qw(dbh);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Log     => qw( debug info );
use Krang::ClassLoader 'ListGroup';
use Carp qw(croak);

# constants

use constant RO_FIELDS => qw( list_id );
use constant RW_FIELDS => qw( name list_group_id parent_list_id );

=head1 NAME

    pkg('List') -  interface to manage lists.

=head1 SYNOPSIS

    use Krang::ClassLoader 'List';

    # create and save new list in Krang::ListGroup 2
    my $list = pkg('List')->new(    name => 'list1',
                                    list_group_id => 2,
                                );

    $list->save();
   
    # create new list in same group with first list as parent 
    my $list2 = pkg('List')->new(   name => 'list2',
                                    list_group_id => 2,
                                    parent_list_id => $list->list_id );

    $list2->save();

    # find and return lists in Krang;:ListGroup 2
    my @found = pkg('List')->find( list_group_id => 2 );

    # delete them both
    $list->delete;
    $list2->delete;

=head1 DESCRIPTION

This class handles management of krang lists. Each list must be a 
member of a L<Krang::ListGroup>, and may optionally have another 
L<Krang::List> as a parent.  

The actual contents of a list is handles by L<Krang::ListItem>.

Currently, krang lists should only be 
created via load on database make as configured in an ElementSet's
HREF[lists.conf|element_system.html] file.

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

use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get                              => [RO_FIELDS],
  get_set                          => [RW_FIELDS];

sub id_meth { 'list_id' }

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
    my $dbh  = dbh;
    my $list_id;

    # if this is not a new list
    if (defined $self->{list_id}) {
        $list_id = $self->{list_id};

        # get rid of list_id
        my @save_fields = grep { $_ ne 'list_id' } RO_FIELDS, RW_FIELDS;

        my $sql =
          'UPDATE list set ' . join(', ', map { "$_ = ?" } @save_fields) . ' WHERE list_id = = ?';
        $dbh->do($sql, undef, (map { $self->{$_} } @save_fields), $list_id);

    } else {
        my @save_fields = (RO_FIELDS, RW_FIELDS);
        my $sql =
            'INSERT INTO list ('
          . join(',', @save_fields)
          . ') VALUES (?'
          . ",?" x ((scalar @save_fields) - 1) . ")";
        debug(__PACKAGE__ . "->save() - $sql");

        $dbh->do($sql, undef, map { $self->{$_} } @save_fields);

        $self->{list_id} = $dbh->{mysql_insertid};
    }
}

=item find()

Find and return list objects with parameters specified.

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
    my $dbh  = dbh;

    my @where;
    my @list_object;

    my %valid_params = (
        list_id        => 1,
        list_group_id  => 1,
        parent_list_id => 1,
        name           => 1,
        name_like      => 1,
        order_by       => 1,
        order_desc     => 1,
        limit          => 1,
        offset         => 1,
        count          => 1,
        ids_only       => 1
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

    # set defaults if need be - default ordering preserves list hierarchy.
    my $order_by   = $args{'order_by'}   ? $args{'order_by'} : 'parent_list_id';
    my $order_desc = $args{'order_desc'} ? 'desc'            : 'asc';
    my $limit      = $args{'limit'}      ? $args{'limit'}    : undef;
    my $offset     = $args{'offset'}     ? $args{'offset'}   : 0;

    # set simple keys
    foreach my $key (keys %args) {
        if (   ($key eq 'name')
            || ($key eq 'list_id')
            || ($key eq 'parent_list_id')
            || ($key eq 'list_group_id'))
        {
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
        $select_string = join(',', (RO_FIELDS, RW_FIELDS));
    }

    my $sql = "select $select_string from list";
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
            $obj = $row->{list_id};
            push(@list_object, $obj);
        } else {
            $obj = bless {%$row}, $self;

            push(@list_object, $obj);
        }
    }
    $sth->finish();
    return @list_object;

}

=item delete()

Delete list specified.

=cut

sub delete {
    my $self      = shift;
    my $list_id   = shift;
    my $dbh       = dbh;
    my $is_object = $list_id ? 0 : 1;

    $list_id = $self->{list_id} if $is_object;

    $dbh->do('DELETE from list where list_id = ?', undef, $list_id);

}

=item $list->serialize_xml(writer => $writer, set => $set)

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self,   %args) = @_;
    my ($writer, $set)  = @args{qw(writer set)};
    local $_;

    # open up <list> linked to schema/list.xsd
    $writer->startTag(
        'list',
        "xmlns:xsi"                     => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation" => 'list.xsd'
    );

    $writer->dataElement(list_id        => $self->list_id);
    $writer->dataElement(list_group_id  => $self->list_group_id);
    $writer->dataElement(name           => $self->name);
    $writer->dataElement(parent_list_id => $self->parent_list_id) if $self->parent_list_id;

    # attach list group
    my ($lg) = pkg('ListGroup')->find(list_group_id => $self->list_group_id);
    $set->add(object => $lg, from => $self);

    # attach parent list if one exists
    if ($self->parent_list_id) {
        my ($parent_list) = pkg('List')->find(list_id => $self->parent_list_id);
        $set->add(object => $parent_list, from => $self);
    }

    # all done
    $writer->endTag('list');
}

=item C<< $list = Krang::List->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML.  See Krang::DataSet for details.

If a matching list (same name, list_group_id, parent_list_id) exists, it
will not be updated, but it wil not be replicated either.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set, $no_update) = @args{qw(xml set no_update)};

    # parse it up
    my $data = pkg('XML')->simple(
        xml           => $xml,
        suppressempty => 1
    );

    # get list_group info
    my $list_group_id = $set->map_id(
        class => pkg('ListGroup'),
        id    => $data->{list_group_id}
    );

    my $parent_id;
    if ($data->{parent_list_id}) {
        $parent_id = $set->map_id(
            class => pkg('List'),
            id    => $data->{parent_list_id}
        );
    }

    my $l;
    if ($parent_id) {
        $l = (
            pkg('List')->find(
                list_group_id  => $list_group_id,
                parent_list_id => $parent_id,
                name           => $data->{name}
            )
        )[0];
    } else {
        $l = (pkg('List')->find(list_group_id => $list_group_id, name => $data->{name}))[0];
    }

    # if matching list exists, don't replicate it
    return $l if $l;

    if ($parent_id) {
        my $new_l = pkg('List')->new(
            name           => $data->{name},
            list_group_id  => $list_group_id,
            parent_list_id => $parent_id
        );
        $new_l->save;
        return $new_l;
    } else {
        my $new_l = pkg('List')->new(name => $data->{name}, list_group_id => $list_group_id);
        $new_l->save;
        return $new_l;
    }
}

=back 

=head1 SEE ALSO

L<Krang::ListGroup>, L<Krang::ListItem>, L<Krang::ElementClass::ListGroup>, 
HREF[The Krang Element System|element_system.html]

=cut

1;

