package Krang::Preference;

=head1 NAME

Krang::Preference - Krang Global Preference API

=head1 SYNOPSIS

  use Krang::Preference;

  # construct object

  # saves object to the DB

  # getters
  ##########

  # setters
  ##########

  # delete the preference from the database

  # a hash of search parameters
  my %params =
  ( order_desc => 1,		# result ascend unless this flag is set
    limit => 5,			# return 5 or less category objects
    offset => 1, 	        # start counting result from the
				# second row
    order_by => 'name'		# sort on the 'name' field
   );

  # any valid object field can be appended with '_like' to perform a
  # case-insensitive sub-string match on that field in the database

  # returns an array of preference objects matching criteria in %params
  my @prefs = Krang::Preference->find( %params );

=head1 DESCRIPTION

=cut


#
# Pragmas/Module Dependencies
##############################
# Pragmas
##########
use strict;
use warnings;

# External Modules
###################
use Carp qw(croak);

# Internal Modules
###################
use Krang;
use Krang::DB qw(dbh);

#
# Package Variables
####################
# Constants
############
# Read-only fields
use constant PREF_RO => qw();

# Read-write fields
use constant PREF_RW => qw();

# Globals
##########

# Lexicals
###########
my %pref_args = map {$_ => 1} PREF_RW;
my %pref_cols = map {$_ => 1} PREF_RO, PREF_RW;

# Constructor/Accessor/Mutator setup
use Krang::MethodMaker	new_with_init => 'new',
			new_hash_init => 'hash_init',
			get => [PREF_RO],
			get_set => [PREF_RW];

=head1 INTERFACE

=head2 FIELDS

Access to fields for this object is provided my Krang::MethodMaker.  The value
of fields can be obtained and set in the following fashion:

 $value = $pref->field_name();
 $pref->field_name( $some_value );

The available fields for a preference object are:

=over 4

=item *

=back

=head2 METHODS

=over 4

=item * $pref = Krang::Preference->new( %params )

Constructor for the module that relies on Krang::MethodMaker.  Validation of
'%params' is performed in init().  The valid fields for the hash are:

=over 4

=item *

=back

=cut

# validates arguments passed to new(), see Class::MethodMaker
# the method croaks if we haven't been provied required params or if an
# invalid key is found in the hash passed to new()
sub init {
    my $self = shift;
    my %args = @_;
    my @bad_args;

    for (keys %args) {
        push @bad_args, $_ unless exists $pref_args{$_};

    }
    croak(__PACKAGE__ . "->init(): The following constructor args are " .
          "invalid: '" . join("', '", @bad_args) . "'") if @bad_args;

    # required arg check...
    for (qw//) {
        croak(__PACKAGE__ . "->init(): Required argument '$_' not present.")
          unless exists $args{$_};
    }

    $self->hash_init(%args);

    return $self;
}


=item * $success = $pref->delete()

=item * $success = Krang::Preference->delete( $pref_id )

Instance or class method that deletes the given preference object from the
database.  It returns '1' following a successful deletion.

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->{pref_id};
    my $dbh = dbh();

    # object reference lookup
    my ($dependents, %info) = $self->dependent_check();
    if ($dependents) {
        my $info = join("\n\t",
                        map {"$_: [" . join(",", @{$info{$_}}). "]"}
                        keys %info);
        croak(__PACKAGE__ . "->delete(): The following objects reference " .
              "this class:\n\t$info");
    }

    $dbh->do("DELETE FROM usr WHERE pref_id = ?", undef, $id);

    return Krang::User->find(pref_id => $id) ? 0 : 1;
}


=item * ($dependents, %info) = $pref->dependent_check()

This method returns the number of dependents and a hash of classes and their
respective object ids that reference the current preference object.  '0' and
undef will be returned if no references are found.

=cut

sub dependent_check {
    my $self = shift;
    my $id = $self->{pref_id};
    my $dependents = 0;
    my ($dbh, %info, $oid, $sth);

    return ($dependents, %info);
}


=item * ($duplicates, %info) = $pref->duplicate_check()

This method checks the database to see if any existing site objects possess any
of the same values as the one in memory.  If this is the case, the number of
duplicates and a hash of ids and the duplicated fields is returned; otherwise,
0 and undef are returned.

=cut

sub duplicate_check {
    my $self = shift;
    my $id = $self->{pref_id};
    my $duplicates = 0;

    my $query = <<SQL;
SQL

    my @params = ();

    # alter query if save() has already been called
    if ($id) {
        push @params, $id;
    }

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);
    my (%info, $row);
    $sth->bind_columns(\(@$row{@{$sth->{NAME_lc}}}));
    while ($sth->fetchrow_arrayref()) {
        for (keys %$row) {
            no warnings;
            if ($self->{$_} eq $row->{$_}) {
                push @{$info{$row->{pref_id}}}, $_;
                $duplicates++;
            }
        }
    }
    $sth->finish();

    return ($duplicates, %info);
}


=item * @prefs = Krang::Preference->find( %params )

=item * @prefs = Krang::Preference->find( pref_id => [1, 1, 2, 3, 5] )

=item * @pref_ids = Krang::Preference->find( ids_only => 1, %params )

=item * $count = Krang::Preference->find( count => 1, %params )

Class method that returns an array of preference objects, preference ids, or a
count.  Case-insensitive sub-string matching can be performed on any valid
field by passing an argument like: "fieldname_like => '%$string%'" (Note: '%'
characters must surround the sub-striqng).  The valid search fields are:

=over 4

=item *

=back

Additional criteria which affect the search results are:

=over 4

=item * ascend

Result set is sorted in ascending order.

=item * count

If this argument is specified, the method will return a count of the categories
matching the other search criteria provided.

=item * ids_only

Returns only preference ids for the results found in the DB, not objects.

=item * limit

Specify this argument to determine the maximum amount of preference objects or
preference ids to be returned.

=item * offset

Sets the offset from the first row of the results to return.

=item * order_by

Specify the field by means of which the results will be sorted.  By default
results are sorted with the 'pref_id' field.

=item * order_desc

Set this flag to '1' to sort results relative to the 'order_by' field in
descending order, by default results sort in ascending order

=back

The method croaks if an invalid search criteria is provided or if both the
'count' and 'ids_only' options are specified.

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my ($fields, @params, $where_clause);

    # are we looking up group ids as well
    my $groups = exists $args{group_ids} ? 1 : 0;

    # grab ascend/descending, limit, and offset args
    my $ascend = delete $args{order_desc} ? 'DESC' : 'ASC';
    my $limit = delete $args{limit} || '';
    my $offset = delete $args{offset} || '';
    my $order_by = delete $args{order_by} || 'pref_id';

    # set search fields
    my $count = delete $args{count} || '';
    my $ids_only = delete $args{ids_only} || '';

    # set bool to determine whether to use $row or %row for binding below
    my $single_column = $ids_only || $count ? 1 : 0;

    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.") if ($count && $ids_only);

    # build list of fields to select
        $fields = $count ? 'count(*)' :
          ($ids_only ? 'category_id' : join(", ", keys %pref_cols));

    # set up WHERE clause and @params, croak unless the args are in
    # %pref_cols
    my @invalid_cols;
    for my $arg (keys %args) {
        my $like = 1 if $arg =~ /_like$/;
        ( my $lookup_field = $arg ) =~ s/^(.+)_like$/$1/e;

        push @invalid_cols, $arg unless exists $pref_cols{$lookup_field};

        if ($arg eq 'pref_id' && ref $args{$arg} eq 'ARRAY') {
            my $tmp = join(" OR ", map {"$arg = ?"} @{$args{$arg}});
            $where_clause .= " ($tmp)";
            push @params, @{$args{$arg}};
        } else {
            my $and = defined $where_clause && $where_clause ne '' ?
              ' AND' : '';
            if (not defined $args{$arg}) {
                $where_clause .= "$and $lookup_field IS NULL";
            } else {
                $where_clause .= $like ? "$and $lookup_field LIKE ?" :
                  "$and $lookup_field = ?";
                push @params, $args{$arg};
            }
        }
    }

    croak("The following passed search parameters are invalid: '" .
          join("', '", @invalid_cols) . "'") if @invalid_cols;

    # construct base query
    my $query = "SELECT $fields FROM pref";

    # add WHERE and ORDER BY clauses, if any
    $query .= " WHERE $where_clause" if $where_clause;
    $query .= " ORDER BY $order_by $ascend" if $order_by;

    # add LIMIT clause, if any
    if ($limit) {
        $query .= $offset ? " LIMIT $offset, $limit" : " LIMIT $limit";
    } elsif ($offset) {
        $query .= " LIMIT $offset, -1";
    }

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);

    # holders for query results and new objects
    my ($row, @prefs);

    # bind fetch calls to $row or %$row
    # a possibly insane micro-optimization :)
    if ($single_column) {
        $sth->bind_col(1, \$row);
    } else {
        $sth->bind_columns(\( @$row{@{$sth->{NAME_lc}}} ));
    }

    # construct preference objects from results
    while ($sth->fetch()) {
        # if we just want count or ids
        if ($single_column) {
            push @prefs, $row;
        } else {
            push @prefs, bless({%$row}, $self);
        }
    }

    # return number of rows if count, otherwise an array of ids or objects
    return $count ? $prefs[0] : @prefs;
}


=item * $pref = $pref->save()

Saves the contents of the preference object in memory to the database.  'pref_id'
will be defined if the call is successful.

The method croaks if the save would result in a duplicate object (i.e.
if any field value required to be unique is not found to be so).  It also
croaks if its database query affects no rows in the database.

=cut

sub save {
    my $self = shift;
    my $id = $self->{pref_id} || 0;
    my @save_fields = grep {$_ ne 'pref_id'} keys %pref_cols;

    # check for duplicates
    my ($duplicates, %info) = $self->duplicate_check();
    if ($duplicates) {
        my $info = join("\n\t",
                        map {"id '$_': " .
                               join(", ", sort @{$info{$_}})}
                        keys %info) . "\n";
        croak(__PACKAGE__ . "->save(): This object duplicates the following " .
              "preference objects:\n\t$info");
    }

    my $query;
    my $dbh = dbh();

    # the object has already been saved once if $id
    if ($id) {
        $query = "UPDATE pref SET " . join(", ", map {"$_ = ?"} @save_fields) .
          " WHERE pref_id = ?";
    } else {
        # build insert query
        $query = "INSERT INTO pref (" . join(',', @save_fields) .
          ") VALUES (?" . ", ?" x (scalar @save_fields - 1) . ")";
    }

    # bind parameters
    my @params = map {$self->{$_}} @save_fields;

    # need pref_id for updates
    push @params, $id if $id;

    # croak if no rows are affected
    croak(__PACKAGE__ . "->save(): Unable to save preference object " .
          ($id ? "id '$id' " : '') . "to the DB.")
      unless $dbh->do($query, undef, @params);

    $self->{pref_id} = $dbh->{mysql_insertid} unless $id;

    return $self;
}


=back

=head1 TO DO

=head1 SEE ALSO

L<Krang>, L<Krang::DB>

=cut


my $quip = <<END;
1
END
