package Krang::User;

=head1 NAME

Krang::User - a means to access information on users

=head1 SYNOPSIS

  use Krang::User;

  # construct object
  my $user = Krang::User->new();		# required

  # saves object to the DB
  $user->save();

  # getters
  my $id = $user->user_id();	# undef until after save()

  # setters

  # delete the category from the database
  $user->delete();

  # a hash of search parameters
  my %params =
  ( order_desc => 'asc',	# sort results in ascending order
    limit => 5,			# return 5 or less user objects
    offset => 1, 	        # start counting result from the
				# second row
    order_by => 'user_id'	# sort on the 'user_id' field
    _like => '%fred%' );

  # any valid object field can be appended with '_like' to perform a
  # case-insensitive sub-string match on that field in the database

  # returns an array of category objects matching criteria in %params
  my @users = Krang::User->find( %params );

=head1 DESCRIPTION

This module serves as a means of adding, deleting, and accessing these objects.

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
use Carp qw(verbose croak);

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
use constant USER_RO => qw(user_id);

# Read-write fields
use constant USER_RW => qw();

# Globals
##########

# Lexicals
###########
my %user_args = map {$_ => 1} qw//;
my %user_cols = map {$_ => 1} USER_RO, USER_RW;

# Constructor/Accessor/Mutator setup
use Krang::MethodMaker	new_with_init => 'new',
			new_hash_init => 'hash_init',
			get => [USER_RO],
			get_set => [USER_RW];


=head1 INTERFACE

=head2 FIELDS

Access to fields for this object is provided my Krang::MethodMaker.  The value
of fields can be obtained and set in the following fashion:

 $value = $category->field_name();
 $category->field_name( $some_value );

The available fields for a category object are:

=over 4

=item * user_id (read-only)

The id of the current object in the database's user table

=back

=head2 METHODS

=over 4

=item * $user = Krang::User->new( %params )

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
        push @bad_args, $_ unless exists $user_args{$_};

    }
    croak(__PACKAGE__ . "->init(): The following constructor args are " .
          "invalid: '" . join("', '", @bad_args) . "'") if @bad_args;

    # required arg check...
    for (qw/name site_id/) {
        croak(__PACKAGE__ . "->init(): Required argument '$_' not present.")
          unless exists $args{$_};
    }

    $self->hash_init(%args);

    return $self;
}


=item * $success = $user->delete()

=item * $success = Krang::user->delete( $user_id )

Instance or class method that deletes the given user object from the database.
It returns '1' following a successful deletion.
# TO DO: what should we do if items belong to or are checked out by the current
# user

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->{user_id};
    my $dbh = dbh();

    my $query = <<SQL;
SQL

    croak(__PACKAGE__ . "->delete(): Objects refering to user '$id' exist")
      if $dbh->selectrow_array($query, undef, ($id));

    $query = "DELETE FROM user WHERE user_id = '$id'";

    $dbh->do($query);

    return 1;
}


=item * @info = $user->duplicate_check()

This method checks the database to see if any existing site objects possess any
of the same values as the one in memory.  If this is the case an array
containing the 'user_id' and the name of the duplicate field is returned,
otherwise, the array will be empty.

=cut

sub duplicate_check {
    my $self = shift;
    my $id = $self->{user_id};
    my (@fields, @id_info, @params, $query, $row, @wheres);

    for (keys %user_cols) {
        next if $_ eq 'user_id';
        push @fields, $_;
        push @wheres, "$_ = ?";
        push @params, $self->{$_};
    }

    $query = "SELECT " . join(",", @fields) .
      "FROM user WHERE " . join(" OR ", @wheres);

    # alter query if save() has already been called
    if ($id) {
        $query .=  "AND user_id != ?\n";
        push @params, $id;
    }

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);
    $sth->bind_columns(\(@$row{@{$sth->{NAME_lc}}}));
    while ($sth->fetchrow_arrayref()) {
        for (keys %$row) {
            push @id_info, $row->{user_id}, $row->{$_}
              if ($self->{$_} && $self->{$_} eq $row->{$_});
        }
    }
    $sth->finish();

    return @id_info;
}


=item * @users = Krang::User->find( %params )

=item * @users = Krang::User->find( category_id => [1, 1, 2, 3, 5] )

=item * @user_ids = Krang::User->find( ids_only => 1, %params )

=item * $count = Krang::User->find( count => 1, %params )

Class method that returns an array of category objects, category ids, or a
count.  Case-insensitive sub-string matching can be performed on any valid
field by passing an argument like: "fieldname_like => '%$string%'" (Note: '%'
characters must surround the sub-string).  The valid search fields are:

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

=item * descend

Results set is sorted in descending order only if the 'ascend' option is not
specified.

=item * ids_only

Returns only category ids for the results found in the DB, not objects.

=item * limit

Specify this argument to determine the maximum amount of category objects or
category ids to be returned.

=item * offset

Sets the offset from the first row of the results to return.

=item * order_by

Specify the field by means of which the results will be sorted.  By default
results are sorted with the 'category_id' field.

=back

The method croaks if an invalid search criteria is provided or if both the
'count' and 'ids_only' options are specified.

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my ($fields, @params, $where_clause);

    # grab ascend/descending, limit, and offset args
    my $ascend = uc(delete $args{order_desc}) || ''; # its prettier w/uc() :)
    my $limit = delete $args{limit} || '';
    my $offset = delete $args{offset} || '';
    my $order_by = delete $args{order_by} || 'category_id';

    # set search fields
    my $count = delete $args{count} || '';
    my $ids_only = delete $args{ids_only} || '';

    # set bool to determine whether to use $row or %row for binding below
    my $single_column = $ids_only || $count ? 1 : 0;

    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.") if ($count && $ids_only);

    # exclude 'element'
    $fields = $count ? 'count(*)' :
      ($ids_only ? 'user_id' : join(", ", grep {$_ ne 'element'}
                                        keys %user_cols));

    # set up WHERE clause and @params, croak unless the args are in
    # USER_RO or USER_RW
    my @invalid_cols;
    for my $arg (keys %args) {
        # don't use element
        next if $arg eq 'element';

        my $like = 1 if $arg =~ /_like$/;
        ( my $lookup_field = $arg ) =~ s/^(.+)_like$/$1/;

        push @invalid_cols, $arg unless exists $user_cols{$lookup_field};

        if ($arg eq 'category_id' && ref $args{$arg} eq 'ARRAY') {
            my $tmp = join(" OR ", map {"user_id = ?"} @{$args{$arg}});
            $where_clause .= " ($tmp)";
            push @params, @{$args{$arg}};
        } else {
            my $and = defined $where_clause && $where_clause ne '' ?
              ' AND' : '';
            $where_clause .= $like ? "$and $lookup_field LIKE ?" :
              " $lookup_field = ?";
            push @params, $args{$arg};
        }
    }

    croak("The following passed search parameters are invalid: '" .
          join("', '", @invalid_cols) . "'") if @invalid_cols;

    # construct base query
    my $query = "SELECT $fields FROM category";

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
    my ($row, @users);

    # bind fetch calls to $row or %$row
    # a possibly insane micro-optimization :)
    if ($single_column) {
        $sth->bind_col(1, \$row);
    } else {
        $sth->bind_columns(\( @$row{@{$sth->{NAME_lc}}} ));
    }

    # construct category objects from results
    while ($sth->fetchrow_arrayref()) {
        # if we just want count or ids
        if ($single_column) {
            push @users, $row;
        } else {
            push @users, bless({%$row}, $self);
        }
    }

    # finish statement handle
    $sth->finish();

    # return number of rows if count, otherwise an array of ids or objects
    return $count ? $users[0] : @users;
}


=item * $user = $user->save()

Saves the contents of the user object in memory to the database.  'user_id'
will be defined if the call is successful.

The method croaks if the save would result in a duplicate object (i.e.
if any field value required to be unique is not found to be so).  It also
croaks if its database query affects no rows in the database.

=cut

sub save {
    my $self = shift;
    my $id = $self->{user_id} || 0;
    my @save_fields = grep {$_ ne 'user_id'} keys %user_cols;

    # check for duplicates
    my ($user_id, $field) = $self->duplicate_check();
    croak(__PACKAGE__ . "->save(): '$field' is a duplicate of user id " .
          "'$user_id'.") if $user_id;

    my $query;
    my $dbh = dbh();

    # the object has already been saved once if $id
    if ($id) {
        $query = "UPDATE user SET " . join(", ", map {"$_ = ?"} @save_fields) .
          " WHERE user_id = ?";
    } else {
        # build insert query
        $query = "INSERT INTO user (" . join(',', @save_fields) .
          ") VALUES (?" . ", ?" x (scalar @save_fields - 1) . ")";
    }

    # bind parameters
    my @params = map {$self->{$_}} @save_fields;

    # need category_id for updates
    push @params, $id if $id;

    # croak if no rows are affected
    croak(__PACKAGE__ . "->save(): Unable to save user object " .
          ($id ? "id '$id' " : '') . "to the DB.")
      unless $dbh->do($query, undef, @params);

    $self->{user_id} = $dbh->{mysql_insertid} unless $id;

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
