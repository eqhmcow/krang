package Krang::Contrib;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader DB => qw(dbh);
use Carp qw(croak);

# constants
use constant FIELDS => qw(contrib_id prefix first middle last suffix email phone media_id bio url);

=head1 NAME

    pkg('Contrib') - storage and retrieval of contributor data

=head1 SYNOPSIS

    # create new contributor object
    my $contrib = pkg('Contrib')->new(  prefix => 'Mr.',
                                        first => 'Matthew',
                                        middle => 'Charles',
                                        last => 'Vella',
                                        email => 'mvella@thepirtgroup.com',
                                        phone => '111-222-3333',
                                        bio => 'This is my bio.',
                                        url => 'http://www.myurlhere.com' );

    # add contributor types (lets pretend contrib_type 1 is 'Writer' and 
    # type 3 is 'Photographer')
    $contrib->contrib_type_ids(1,3);

    # save this contributor to the database
    $contrib->save();

    # now that it is saved we can get its id
    my $contrib_id = $contrib->contrib_id();

    # find this contributor by id
    my @contribs = pkg('Contrib')->find( contrib_id => $contrib_id );

    # list contributor type ids (will return 1,3)
    @contrib_type_ids = $contribs[0]->contrib_type_ids();

    # list contrib type names (will return 'Writer', 'Photographer');
    @contrib_type_names = $contribs[0]->contrib_type_names();

    # change contributor contrib type ids, effectively removing writer type (1)
    $contribs[0]->contrib_type_ids(3);

    # save contributor, making changes permanent
    $contribs[0]->save();

    # delete contributor
    $contribs[0]->delete();


=head1 DESCRIPTION

This class handles the storage and retrieval of contributor data to/from the database. Contributor type ids come from Krang::AdminPrefs (??), but are associated to contributors here.

=head1 INTERFACE

=head2 METHODS

=over 

=item $contrib = Krang::Contrib->new()

new() suports the following name-value arguments:

=over

=item prefix

=item first

=item middle

=item last

=item suffix

=item email

=item phone

=item bio

=item url

All of the above are simply fields for storing arbitrary metadata

=back

=cut

# setup exceptions
use Exception::Class ('Krang::Contrib::DuplicateName' => {fields => ['contrib_id']},);

use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get_set => [qw( contrib_id prefix first middle last suffix email phone bio url )],
  list    => [qw( contrib_type_ids )];

sub id_meth { 'contrib_id' }

sub init {
    my $self = shift;
    my %args = @_;

    $args{contrib_type_ids} ||= [];

    # finish the object
    $self->hash_init(%args);

    return $self;
}

=item $contrib_id = $contrib->contrib_id()

Returns the unique id assigned the contributor object.  Will not be populated until $contrib->save() is called the first time.

=item $contrib->prefix()

=item $contrib->first()

=item $contrib->middle()

=item $contrib->last()

=item $contrib->suffix()

=item $contrib->email()

=item $contrib->phone()

=item $contrib->bio()

=item $contrib->url()

Gets/sets the value.

=item $contrib->full_name()

A read-only method that returns a concatenated string containing all attributes that make up the contributor's name.  Any unassigned attributes will be omitted.

full_name takes the form of: B<prefix() first() middle() last(), suffix()>

=cut

sub full_name {
    my $self = shift;
    return join(
        " ", grep { defined and length }
          map { $self->{$_} } (qw(prefix first middle last))
    ) . (defined $self->{suffix} and length $self->{suffix} ? ", $self->{suffix}" : "");
}

=item $contrib->image()

Returns the Krang::Media object associated with this contributor.  Passing a Krang::Media object sets the media object associated with this contributor (overwriting any current image).

=cut

sub image {
    my $self = shift;
    unless (@_) {
        if (exists($self->{media_id}) && defined($self->{media_id})) {
            my ($image) = pkg('Media')->find(media_id => $self->{media_id});
            return $image;
        } else {
            return undef;
        }
    }

    my $image = shift;
    unless ($image->isa('Krang::Media')) {
        croak __PACKAGE__ . ": parameter is not a pkg('Media') object";
    }

    $self->{media_id} = $image->media_id;

    return;
}

=item $contrib->selected_contrib_type()

Temporary value used by assets (media, story, etc) to show which
contrib type the contrib object they are referring belongs to.
Contains a single contrib_type_id from contrib_type_ids.

=cut

sub selected_contrib_type {
    my $self = shift;
    return $self->{selected_contrib_type} unless @_;
    $self->{selected_contrib_type} = $_[0];
}

=item $contrib->contrib_type_ids()

Returns an array of contrib_type_id's associated with this contributor.  Passing in array of ids sets them (overwriting any current type ids).

=item $contrib->contrib_type_names()

Returns array of contrib type names, matching order of contrib_type_ids.

=cut

sub contrib_type_names {
    my $self = shift;
    my $dbh  = dbh;
    my @contrib_type_names;

    foreach my $type_id (@{$self->{contrib_type_ids}}) {
        my $sth = $dbh->prepare('SELECT type from contrib_type where contrib_type_id = ?');
        $sth->execute($type_id);
        push @contrib_type_names, $sth->fetchrow_array();
    }

    return @contrib_type_names;
}

=item $contrib->save()

Save contributor oject to the database. Will set contrib_id if first save.

Contributor names much be unique.  Specifically, no two contributors many have the same
first, middle, and last name.  If you attempt to save a duplicate contributor
$contrib->save() will throw an exception or type Krang::Contrib::DuplicateName.
This exception provides a contrib_id of the existing contributor who already has this name.

=cut

sub save {
    my $self = shift;
    my $dbh  = dbh;

    # make sure it's got a unique URI
    $self->verify_unique();

    # if this is not a new contrib object
    if (defined $self->{contrib_id}) {
        my $contrib_id = $self->{contrib_id};

        # get rid of contrib_id from FIELDS, we don't have to reset it.
        my @fields = FIELDS;
        @fields = splice(@fields, 1);

        $dbh->do(
            'UPDATE contrib set '
              . join(',', (map { "$_ = ?" } @fields))
              . ' WHERE contrib_id = ? ',
            undef, (map { $self->{$_} } @fields), $contrib_id
        );

        # remove all contributor - contributor tyoe relations, we are going to re-add them
        $dbh->do('DELETE from contrib_contrib_type where contrib_id = ?', undef, $contrib_id);
        foreach my $type_id (@{$self->{contrib_type_ids}}) {
            $dbh->do('INSERT into contrib_contrib_type (contrib_id, contrib_type_id) VALUES (?,?)',
                undef, $contrib_id, $type_id);
        }
    } else {
        $dbh->do(
            'INSERT INTO contrib ('
              . join(',', FIELDS)
              . ') VALUES ('
              . join(',', ('?') x FIELDS) . ')',
            undef,
            map { $self->{$_} } FIELDS
        );

        $self->{contrib_id} = $dbh->{mysql_insertid};
        my $contrib_id = $self->{contrib_id};

        foreach my $type_id (@{$self->{contrib_type_ids}}) {
            $dbh->do('INSERT into contrib_contrib_type (contrib_id, contrib_type_id) VALUES (?,?)',
                undef, $contrib_id, $type_id);
        }

    }
}

=item $contrib->delete() || Krang::Media->delete($contrib_id)

Permanently delete contrib object or contrib object with given id and contrib type associations.

=cut

sub delete {
    my $self       = shift;
    my $contrib_id = shift;
    my $dbh        = dbh;

    $contrib_id = $self->{contrib_id} if (not $contrib_id);

    croak("No contrib_id specified for delete!") if not $contrib_id;

    $dbh->do('DELETE from story_contrib where contrib_id = ?',        undef, $contrib_id);
    $dbh->do('DELETE from media_contrib where contrib_id = ?',        undef, $contrib_id);
    $dbh->do('DELETE from contrib where contrib_id = ?',              undef, $contrib_id);
    $dbh->do('DELETE from contrib_contrib_type where contrib_id = ?', undef, $contrib_id);
}

=item @contrib = Krang::Contrib->find($param)

Find and return contributors with with parameters specified. Supported paramter keys:

=over 4


=item *

contrib_id

=item *

first

=item *

last

=item *

simple_search - will search first, middle, last for matching LIKE strings

=item *

exclude_contrib_ids - pass array ref of IDs to be excluded from the result set


=item * 

order_by - field(s) to order search by, defaults to last,first. Can pass in list.


=item *

order_desc - results will be in ascending order unless this is set to 1 (making them descending).


=item *

limit - limits result to number passed in here, else no limit.


=item *

offset - offset results by this number, else no offset.


=item *

ids_only - return only contrib_ids, not objects if this is set true.


=item *

count - return only a count if this is set to true. Cannot be used with ids_only.


=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my $dbh  = dbh;
    my @where;
    my @contrib_object;
    my $where_string;

    my %valid_params = (
        contrib_id          => 1,
        first               => 1,
        last                => 1,
        simple_search       => 1,
        exclude_contrib_ids => 1,
        order_by            => 1,
        order_desc          => 1,
        limit               => 1,
        offset              => 1,
        count               => 1,
        ids_only            => 1
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

    my $order_desc = $args{'order_desc'} ? 'desc' : 'asc';
    $args{order_by} ||= 'last,first';
    my $order_by = join(
        ',', map { "$_ $order_desc" }
          split(',', $args{'order_by'})
    );
    my $limit  = $args{'limit'}  ? $args{'limit'}  : undef;
    my $offset = $args{'offset'} ? $args{'offset'} : 0;

    foreach my $key (keys %args) {
        if (($key eq 'contrib_id') || ($key eq 'first') || ($key eq 'last')) {
            push @where, $key;
        }
    }

    $where_string = join ' and ', (map { "$_ = ?" } @where);

    # exclude_contrib_ids: Specifically exclude contribs with IDs in this set
    if ($args{'exclude_contrib_ids'}) {
        my $exclude_contrib_ids_sql_set = "'" . join("', '", @{$args{'exclude_contrib_ids'}}) . "'";

        # Append to SQL where clause
        $where_string .= " and " if ($where_string);
        $where_string .= "contrib.contrib_id NOT IN ($exclude_contrib_ids_sql_set)";
    }

    # simple_search: add like search on first, last, middle for all simple_search words
    if ($args{'simple_search'}) {
        my @words = split(/\s+/, $args{'simple_search'});
        foreach my $word (@words) {
            if ($where_string) {
                $where_string .= " and concat_ws(' ', first, middle, last) like ?";
            } else {
                $where_string = "concat_ws(' ', first, middle, last) like ?";
            }
            push(@where, $word);

            # escape any literal SQL wildcard chars
            $word =~ s/_/\\_/g;
            $word =~ s/%/\\%/g;
            $args{$word} = '%' . $word . '%';
        }
    }

    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*)';
    } elsif ($args{'ids_only'}) {
        $select_string = 'contrib_id';
    } else {
        my @fields = FIELDS;
        $select_string = 'contrib.contrib_id,' . join(',', splice(@fields, 1));
    }

    my $from = 'contrib';

    # Order by type needs data from tables 'contrib_type' and 'contrib_contrib_type'
    if ($args{'order_by'} eq 'type') {
        $order_by      .= ', last asc, first asc';
        $select_string .= ", contrib_type.contrib_type_id as contrib_type_id" unless $args{count};
        $where_string  .= " and " if ($where_string);
        $where_string  .= "contrib.contrib_id = contrib_contrib_type.contrib_id"
          . " and contrib_type.contrib_type_id = contrib_contrib_type.contrib_type_id";
        $from .= ', contrib_type, contrib_contrib_type';
    }

    my $sql = "select $select_string from $from";
    $sql .= " where " . $where_string if $where_string;
    $sql .= " order by $order_by ";

    # add limit and/or offset if defined
    if ($limit) {
        $sql .= " limit $offset, $limit";
    } elsif ($offset) {
        $sql .= " limit $offset, 18446744073709551615";
    }

    my $sth = $dbh->prepare($sql);
    $sth->execute(map { $args{$_} } @where) || croak("Unable to execute statement $sql");
    while (my $row = $sth->fetchrow_hashref()) {
        my $obj;
        if ($args{'count'}) {
            return $row->{'count(*)'};
        } elsif ($args{'ids_only'}) {
            $obj = $row->{contrib_id};
        } else {
            $obj = bless {}, $self;
            %$obj = %$row;

            # load contrib_type ids
            if ($obj->{contrib_type_id}) {
                $obj->{contrib_type_ids} = [$obj->{contrib_type_id}];
            } else {
                my $result = $dbh->selectcol_arrayref(
                    'SELECT contrib_type_id FROM contrib_contrib_type
                           WHERE contrib_id = ?', undef, $obj->{contrib_id}
                );
                $obj->{contrib_type_ids} = $result || [];
            }
        }
        push(@contrib_object, $obj);
    }
    $sth->finish();
    return @contrib_object;
}

=item C<< $contrib->serialize_xml(writer => $writer, set => $set) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self,   %args) = @_;
    my ($writer, $set)  = @args{qw(writer set)};
    local $_;

    # open up <contrib> linked to schema/contrib.xsd
    $writer->startTag(
        'contrib',
        "xmlns:xsi"                     => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation" => 'contrib.xsd'
    );

    # basic fields -- media handled below.
    $writer->dataElement($_ => $self->{$_}) for (grep { $_ ne 'media_id' } (FIELDS));

    # contrib types
    $writer->dataElement(contrib_type => $_) for $self->contrib_type_names;

    # media
    if (exists($self->{media_id}) && defined($self->{media_id})) {
        my ($media) = pkg('Media')->find(media_id => $self->{media_id});
        if (defined($media)) {
            $writer->dataElement(media_id => $self->{media_id});
            $set->add(object => $media, from => $self);
        }
    }

    # all done
    $writer->endTag('contrib');
}

=item C<< $contrib = Krang::Contrib->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML.  See Krang::DataSet for details.

If an incoming contributor has the same first, middle and last name as
an existing contributor then deserialize_xml() will update the
contributor object rather than create a new one.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set, $no_update) = @args{qw(xml set no_update)};

    # parse it up
    my $data = pkg('XML')->simple(
        xml           => $xml,
        forcearray    => ['contrib_type'],
        suppressempty => 1
    );

    # create new contributor object
    my $contrib = pkg('Contrib')->new();

    # set fields
    $contrib->$_($data->{$_}) for (grep { $_ ne 'contrib_id' && $_ ne 'media_id' } (FIELDS));

    # get media object
    if (exists($data->{media_id})) {
        my $media_id = $set->map_id(
            class => pkg('Media'),
            id    => $data->{media_id}
        );
        my ($media) = pkg('Media')->find(media_id => $media_id);
        $contrib->image($media);
    }

    # get hash of contrib type names to ids
    my %contrib_types = reverse pkg('Pref')->get('contrib_type');

    # get ids for contrib types
    my @contrib_type_ids;
    foreach my $type (@{$data->{contrib_type}}) {
        unless (exists $contrib_types{$type}) {

            # create the missing contrib type
            $contrib_types{$type} = pkg('Pref')->add_option('contrib_type', $type);
        }
        push(@contrib_type_ids, $contrib_types{$type});
    }

    # add contributor types
    $contrib->contrib_type_ids(@contrib_type_ids);

    # save this contributor to the database
    eval { $contrib->save() };

    # was it a dup?
    if ($@ and ref $@ and $@->isa('Krang::Contrib::DuplicateName')) {
        my $dup_id = $@->contrib_id;

        # if not updating this fatal
        Krang::DataSet::DeserializationFailed->throw(message => "A contributor with the name "
              . "$data->{first} $data->{last} already exists and "
              . "no_update is set.")
          if $no_update;

        # otherwise, switch to this ID and run the update
        $contrib->{contrib_id} = $dup_id;
        $contrib->save();
    } elsif ($@) {
        die $@;
    }

    return $contrib;
}

###########################
####  PRIVATE METHODS  ####
###########################

sub verify_unique {
    my $self = shift;
    my $dbh  = dbh;

    # build up where clause and param list
    my (@where, @param);

    # exception for self if saved
    if ($self->{contrib_id}) {
        push @where, 'contrib_id != ?';
        push(@param, $self->{contrib_id});
    }

    # missing name could be '' or NULL, treat them the same
    foreach my $name (qw(first middle last)) {
        if ($self->{$name}) {
            push @where, "$name = ?";
            push(@param, $self->{$name});
        } else {
            push @where, "($name = ? OR $name IS NULL)";
            push(@param, "");
        }
    }

    my $query = 'SELECT contrib_id FROM contrib WHERE ' . join(' AND ', @where);

    # lookup dup
    my ($dup_id) = $dbh->selectrow_array($query, undef, @param);

    # throw exception on dup
    Krang::Contrib::DuplicateName->throw(
        message    => "duplicate name",
        contrib_id => $dup_id
    ) if $dup_id;
}

=back

=cut

1;

