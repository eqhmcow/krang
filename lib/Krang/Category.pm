package Krang::Category;

=head1 NAME

Krang::Category - a means access to information on categories

=head1 SYNOPSIS

  use Krang::Category;

  # construct object
  my $category = Krang::Category->new(element_id => 1, 		# optional
			      	      name => '/category/X/',	# required
			      	      parent_id => 1,	  	# optional
			      	      site_id => 1);		# required

  # saves object to the DB
  $category->save();

  # getters
  my $id = $category->category_id();	# undef until after save()
  my $name = $category->name();
  my $id = $category->parent_id();
  my $path = $category->path();		# undef until after save()
  my $id = $site->id();

  # setter
  $category->element_id( 33 );

  # delete the category from the database
  $category->delete();

  # a hash of search parameters
  my %params =
  ( ascend => 1,		# sort results in ascending order
    limit => 5,			# return 5 or less category objects
    offset => 1, 	        # start counting result from the
				# second row
    order_by => 'path'		# sort on the 'path' field
    name_like => '%bob%',	# match categories with name LIKE '%bob%'
    path_like => '%fred%',
    parent_id => 8,
    site_id => 9 );

  # any valid object field can be appended with '_like' to perform a
  # case-insensitive sub-string match on that field in the database

  # returns an array of category objects matching criteria in %params
  my @categories = Krang::Category->find( %params );

=head1 DESCRIPTION

This module serves as a means of adding, deleting, accessing category objects
for a given Krang instance.

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
use Data::Dumper;
use Time::Piece::MySQL;

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
use constant CATEGORY_RO => qw(creation_date
			       category_id
			       name
			       parent_id
			       path
			       site_id);

# Read-write fields
use constant CATEGORY_RW => qw(element_id);

# Globals
##########

# Lexicals
###########
my %category_args = qw(element_id name parent_id site_id);
my %category_cols = map {$_ => 1} CATEGORY_RO, CATEGORY_RW;

# Constructor/Accessor/Mutator setup
use Krang::MethodMaker	new_with_init => 'new',
			new_hash_init => 'hash_init',
			get => [CATEGORY_RO],
			get_set => [CATEGORY_RW];


=head1 INTERFACE

=head2 FIELDS

Access to fields for this object is provided my Krang::MethodMaker.  The value
of fields can be obtained and set in the following fashion:

 $value = $category->field_name();
 $category->field_name( $some_value );

The available fields for a category object are:

=over 4

=item * category_id (read-only)

The object's id in the category table

=item * creation_date (read-only)

The datetime when this object was first saved to the database

=item * element_id

Id in the element table of this object's element

=item * name (read-only)

The display name of the category i.e. '/gophers'

=item * parent_id (read-only)

Id of this categories parent category, if any

=item * path (read-only)

The full system path for this category

=item * site_id (read-only)

Id in the site table of this object's site

=back

=head2 METHODS

=over 4

=item * $category = Krang::Category->new( %params )

Constructor for the module that relies on Krang::MethodMaker.  Validation of
'%params' is performed in init().  The valid fields for the hash are:

=over 4

=item * element_id

=item * name

=item * parent_id

=item * site_id

=back

=cut

# validates arguments passed to new(), see Class::MethodMaker
# the method croaks if an invalid key is found in the hash passed to new()
sub init {
    my $self = shift;
    my %args = @_;
    my @bad_args;

    for (keys %args) {
        push @bad_args, $_ unless exists $category_args{$_};
    }
    croak(__PACKAGE__ . "->init(): The following constructor args are " .
          "invalid: '" . join("', '", @bad_args) . "'") if @bad_args;

    $self->hash_init(%args);

    return $self;
}


=item * $success = $category->delete()

=item * $success = Krang::Category->delete( $category_id )

Instance or class method that deletes the given category from the database.  It
returns '1' following a successful deletion.  The method will croak if the
category has subcategories or if any objects refer to it (media, stories,
templates).

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->{category_id};
    my $dbh = dbh();

    # First pass...
    my $query = <<SQL;
SELECT 1
FROM category c, media m, story s, template t
WHERE c.parent_id = ? OR m.category_id = ? OR s.category_id = ? t.category = ?
SQL
    croak(__PACKAGE__ . "->delete(): Objects refering to category still exist")
      if $dbh->do($query, undef, ($id, $id, $id, $id));

    $query = "DELETE FROM category WHERE category_id = '$id'";
    $dbh->do($query);

    return 1;
}


=item * @categories = Krang::Category->find( %params )

=item * @categories = Krang::Category->find( category_id => [1, 1, 2, 3, 5] )

=item * @category_ids = Krang::Category->find( ids_only => 1, %params )

=item * $count = Krang::Category->find( count => 1, %params )

Class method that returns an array of category objects, category ids, or a count.
Case-insensitive sub-string matching can be performed on any valid field by
passing an argument like: "fieldname_like => '%$string%'" (Note: '%'
characters must surround the sub-string).  The valid search fields are:

=over 4

=item * category_id

=item * creation_date

=item * element_id

=item * name

=item * parent_id

=item * path

=item * site_id

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
    my $ascend = delete $args{ascend} || '';
    my $descend = delete $args{descend} || '';
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

    $fields = $count ? 'count(*)' :
      ($ids_only ? 'category_id' : join(", ", keys %category_cols));

    # set up WHERE clause and @params, croak unless the args are in
    # CATEGORY_RO or CATEGORY_RW
    my @invalid_cols;
    for my $arg (keys %args) {
        my $like = 1 if $arg =~ /_like$/;
        ( my $lookup_field = $arg ) =~ s/^(.+)_like$/$1/;

        push @invalid_cols, $arg unless exists $category_cols{$lookup_field};

        if ($arg eq 'category_id' && ref $args{$arg} eq 'ARRAY') {
            my $tmp = join(" OR ", map {"category_id = ?"} @{$args{$arg}});
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
    $query .= " ORDER BY $order_by" if $order_by;
    $query .= $ascend ? " ASC" : ($descend ? " DESC" : "");

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
    my ($row, @categories);

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
            push @categories, $row;
        } else {
            push @categories, bless({%$row}, $self);
        }
    }

    # finish statement handle
    $sth->finish();

    # return number of rows if count, otherwise an array of ids or objects
    return $count ? $categories[0] : @categories;
}


=item * $category = $category->save()

Saves the contents of the category object in memory to the database.  Both
'category_id' and 'path' will be defined if the call is successful.

The method croaks if the save would result in a duplicate category object (i.e.
if the object has the same path or url as another object).  It also croaks if
its database query affects no rows in the database.

=cut

sub save {
    my $self = shift;
    my $id = $self->{category_id} || '';
    my @lookup_fields = qw/name path/;
    my @save_fields = grep {$_ ne 'category_id'} keys %category_cols;

    # prevent creation of duplicate objects or saving of duplicate fields
    my $query = "SELECT category_id, name, path FROM category WHERE " .
      join(" OR ", map {"$_ = ?"} @lookup_fields) . " LIMIT 1";
    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(map {$self->{$_}} @lookup_fields);

    # reference into which result are fetched
    my $row;
    $sth->bind_columns(\(@$row{@{$sth->{NAME_lc}}}));
    while ($sth->fetch()) {
        for (@lookup_fields) {
            croak(__PACKAGE__ . "->save(): Object field '$_' is the same " .
                  "as that of object id '$row->{category_id}'.")
              if $self->{$_} eq $row->{$_};
        }
    }
    $sth->finish();

    if ($id) {
        $query = "UPDATE category SET " .
          join(", ", map {"$_ = ?"} @save_fields) .
            " WHERE category_id = ?";
    } else {
        # calculate path...
        if ($self->{parent_id}) {
            $query = "SELECT path FROM category WHERE category_id = " .
              "'$self->{parent_id}'";
        } else {
            # i guess publish_path is right...
            $query = "SELECT publish_path FROM site WHERE site_id = " .
              "'$self->{site_id}'";
        }
        my ($path) = $dbh->selectrow_array($query);

        # set fields
        my $time = localtime();
        $self->{creation_date} = $time->strftime("%Y-%m-%d %T");
        $self->{path} = File::Spec->catdir($path, $self->{name});

        # build query
        $query = "INSERT INTO category (" . join(',', @save_fields) .
          ") VALUES (?" . ", ?" x (scalar @save_fields - 1) . ")";
    }

    # bind parameters
    my @params = map {$self->{$_}} @save_fields;

    # need category_id for updates
    push @params, $id if $id;

    # croak if no rows are affected
    croak(__PACKAGE__ . "->save(): Unable to save category object " .
          ($id ? "id '$id' " : '') . "to the DB.")
      unless $dbh->do($query, undef, @params);

    $self->{category_id} = $dbh->{mysql_insertid} unless $id;

    return $self;
}


=back

=head1 TO DO

Lots.

=head1 SEE ALSO

L<Krang>, L<Krang::DB>

=cut


my $quip = <<END;
Nothing yet...
END
