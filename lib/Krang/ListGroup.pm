package Krang::ListGroup;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader DB      => qw(dbh);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Log     => qw( debug info );
use Carp qw(croak);

# constants

use constant RO_FIELDS => qw( list_group_id );
use constant RW_FIELDS => qw( name description );

=head1 NAME

Krang::ListGroup -  interface to manage list groups.

=head1 SYNOPSIS

    use Krang::ClassLoader 'ListGroup';

    my $group = pkg('ListGroup')->new(  name => 'testlistgroup',
                                        description => 'desc here' );

    $group->save;

    my @groups_found = pkg('ListGroup')->find( name => 'testlistgroup' );

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

use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get                              => [RO_FIELDS],
  get_set                          => [RW_FIELDS];

sub id_meth { 'list_group_id' }

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
    my $dbh  = dbh;
    my $list_group_id;

    # if this is not a new list group
    if (defined $self->{list_group_id}) {
        $list_group_id = $self->{list_group_id};

        # get rid of list_group_id
        my @save_fields = grep { $_ ne 'list_group_id' } RO_FIELDS, RW_FIELDS;

        my $sql =
            'UPDATE list_group set '
          . join(', ', map { "$_ = ?" } @save_fields)
          . ' WHERE list_group_id = ?';
        $dbh->do($sql, undef, (map { $self->{$_} } @save_fields), $list_group_id);

    } else {
        my @save_fields = (RO_FIELDS, RW_FIELDS);
        my $sql =
            'INSERT INTO list_group ('
          . join(',', @save_fields)
          . ') VALUES (?'
          . ",?" x ((scalar @save_fields) - 1) . ")";
        debug(__PACKAGE__ . "->save() - $sql");

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
    my $dbh  = dbh;

    my @where;
    my @lg_object;

    my %valid_params = (
        list_group_id => 1,
        name          => 1,
        name_like     => 1,
        order_by      => 1,
        order_desc    => 1,
        limit         => 1,
        offset        => 1,
        count         => 1,
        ids_only      => 1
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
    my $order_by   = $args{'order_by'}   ? $args{'order_by'} : 'name';
    my $order_desc = $args{'order_desc'} ? 'desc'            : 'asc';
    my $limit      = $args{'limit'}      ? $args{'limit'}    : undef;
    my $offset     = $args{'offset'}     ? $args{'offset'}   : 0;

    # set simple keys
    foreach my $key (keys %args) {
        if (($key eq 'name') || ($key eq 'list_group_id')) {
            push @where, $key;
        }
    }

    my $where_string = join ' and ', (map { "$_ = ? " } @where);

    if ($args{name_like}) {
        $where_string = $where_string ? ' and name like ? ' : ' name like ?';
        push(@where, 'name_like');
    }

    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*) as count';
    } elsif ($args{'ids_only'}) {
        $select_string = 'list_group_id';
    } else {
        $select_string = join(',', (RO_FIELDS, RW_FIELDS));
    }

    my $sql = "select $select_string from list_group";
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
            $obj = $row->{list_group_id};
            push(@lg_object, $obj);
        } else {
            $obj = bless {%$row}, $self;

            push(@lg_object, $obj);
        }
    }
    $sth->finish();
    return @lg_object;

}

=item delete()

Delete list group specified.

=cut

sub delete {
    my $self          = shift;
    my $list_group_id = shift;
    my $dbh           = dbh;
    my $is_object     = $list_group_id ? 0 : 1;

    $list_group_id = $self->{list_group_id} if $is_object;

    $dbh->do('DELETE from list_group where list_group_id = ?', undef, $list_group_id);

}

=item $list_group->serialize_xml(writer => $writer, set => $set)

Serialize as XML.  See L<Krang::DataSet> for details.

=cut

sub serialize_xml {
    my ($self,   %args) = @_;
    my ($writer, $set)  = @args{qw(writer set)};
    local $_;

    # open up <list_group> linked to schema/list_group.xsd
    $writer->startTag(
        'list_group',
        "xmlns:xsi"                     => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation" => 'list_group.xsd'
    );

    $writer->dataElement(list_group_id => $self->list_group_id);
    $writer->dataElement(name          => $self->name);
    $writer->dataElement(description   => $self->description);

    # all done
    $writer->endTag('list_group');
}

=item C<< $list_group = Krang::ListGroup->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML.  See Krang::DataSet for details.

If an incoming list group has the same name as an existing list group then an
update will occur, unless no_update is set.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set, $no_update) = @args{qw(xml set no_update)};

    # parse it up
    my $data = pkg('XML')->simple(
        xml           => $xml,
        suppressempty => 1
    );

    # is there an existing object?
    my $lg = (pkg('ListGroup')->find(name => $data->{name}))[0] || '';

    if ($lg) {

        debug(__PACKAGE__ . "->deserialize_xml : found list group");

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A list group object with the name '$data->{name}' already "
              . "exists and no_update is set.")
          if $no_update;

        # update simple fields
        $lg->description($data->{description});
        $lg->save();

    } else {
        $lg = pkg('ListGroup')->new(name => $data->{name}, description => $data->{description});
        $lg->save;
    }

    return $lg;
}

=back 

=head1 SEE ALSO

L<Krang::List>, L<Krang::ListItem>, L<Krang::ElementClass::ListGroup>, 
HREF[The Krang Element System|element_system.html]



=cut

1;

