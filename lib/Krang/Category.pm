package Krang::Category;

=head1 NAME

Krang::Category - a means to access information on categories

=head1 SYNOPSIS

  use Krang::Category;

  # construct object
  my $category = Krang::Category->new(dir => 'category',	# required
			      	      parent_id => 1,	  	# optional
			      	      site_id => 1);		# required

  # saves object to the DB
  $category->save();

  # getters
  my $element = $category->element();
  my $dir = $category->dir();
  my $id = $category->parent_id();
  my $id = $category->site_id();

  my $id = $category->category_id();	# undef until after save()
  my $id = $category->element_id();	# undef until after save()
  my $url = $category->url();		# undef until after save()

  # setter
  $category->element( $element );
  $category->dir( $some_single_level_dirname );

  # delete the category from the database
  $category->delete();

  # a hash of search parameters
  my %params =
  ( order_desc => 'asc',	# sort results in ascending order
    limit => 5,			# return 5 or less category objects
    offset => 1, 	        # start counting result from the
				# second row
    order_by => 'url'		# sort on the 'url' field
    dir_like => '%bob%',	# match categories with dir LIKE '%bob%'
    parent_id => 8,
    site_id => 9,
    url_like => '%fred%' );

  # any valid object field can be appended with '_like' to perform a
  # case-insensitive sub-string match on that field in the database

  # returns an array of category objects matching criteria in %params
  my @categories = Krang::Category->find( %params );

=head1 DESCRIPTION

Categories serve three purposes in Krang.  They serve as a means of dividing a
sites content into distinct areas.  Consequently, all content sharing the
property of "being chiefly about 'X'" should be placed within category 'X'.  A
category's dir, such as '/X', translates to both a relative system filepath for
preview and publish output and a URL relative path.  For example category '/X'
would map to $site->publish_path() . '/X' as well as 'http://' . $site->url() .
'/X'.

Secondly, categories serve as a data container.  The 'element' field of a
category object is a Krang::Element wherein arbitrary information about the
category may be stored.

Thirdly, once a template object is associated with its element, a category
serves to provide a layout container for story content that belongs to it.  All
of the fields defined in the category's element will be available to this
template and may be used to derive category-specific layout behavior.

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
use File::Spec;

# Internal Modules
###################
use Krang;
use Krang::DB qw(dbh);
use Krang::Element;

#
# Package Variables
####################
# Constants
############
# Read-only fields
use constant CATEGORY_RO => qw(category_id
			       element_id
			       url);

# Read-write fields
use constant CATEGORY_RW => qw(dir
			       element
			       parent_id
			       site_id);

# Globals
##########

# Lexicals
###########
my %category_args = map {$_ => 1} qw(dir parent_id site_id);
my %category_cols = map {$_ => 1} CATEGORY_RO, CATEGORY_RW, 'dir';

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

=item * element

Element object associated with the given category object belonging to the
special element class 'category'

=item * element_id

Id in the element table of this object's element

=item * dir

The display name of the category i.e. '/gophers'

=item * parent_id

Id of this categories parent category, if any

=item * site_id

Id in the site table of this object's site

=item * url (read-only)

The full URL to this category

=back

=head2 METHODS

=over 4

=item * $category = Krang::Category->new( %params )

Constructor for the module that relies on Krang::MethodMaker.  Validation of
'%params' is performed in init().  The valid fields for the hash are:

=over 4

=item * dir

=item * parent_id

=item * site_id

=back

=cut

# validates arguments passed to new(), see Class::MethodMaker
# the method croaks if we haven't been provied a 'dir' and 'site_id', if an
# invalid key is found in the hash passed to new(), or if 'dir' contains more
# than '/'
sub init {
    my $self = shift;
    my %args = @_;
    my (@bad_args, @required_args);

    for (keys %args) {
        push @bad_args, $_ unless exists $category_args{$_};

    }
    croak(__PACKAGE__ . "->init(): The following constructor args are " .
          "invalid: '" . join("', '", @bad_args) . "'") if @bad_args;

    # required arg check...
    for (qw/dir site_id/) {
        croak(__PACKAGE__ . "->init(): Required argument '$_' not present.")
          unless exists $args{$_};
    }

    croak(__PACKAGE__ . "->init(): 'dir' names can only represent a " .
          "directory directly beneath its parent.")
      if $args{dir} =~ m|/[^/]+/|;

    $self->hash_init(%args);

    # set '_old_dir' to 'dir' to make changes to 'dir' detectable
    $self->{_old_dir} = $self->{dir};

    # define element
    $self->{element} = Krang::Element->new(class => 'category');

    return $self;
}


=item * $success = $category->delete()

=item * $success = Krang::Category->delete( $category_id )

Instance or class method that deletes the given category and its associated
element from the database.  It returns '1' following a successful deletion.
The method will croak if the category has subcategories or if any objects
refer to it (media, stories, templates).

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->{category_id};
    my $element_id = $self->{element_id} ||
      (Krang::Category->find(category_id => $id))[0]->{element_id};
    my $dbh = dbh();

    my $query = "SELECT 1 FROM %s WHERE %s = ?";

    my @queries = ([qw/category parent_id/],
                   [qw/media category_id/],
                   [qw/story_category category_id/],
                   [qw/template category_id/]);

    for (@queries) {
        my ($oid) = $dbh->selectrow_array(sprintf($query, @$_), undef, $id);
        croak(__PACKAGE__ . "->delete(): $_->[0] object id '$_->[1]' still " .
              "refers to this category.  You must remove it first.") if $oid;
    }

    $query = "DELETE FROM category WHERE category_id = '$id'";
    my $e_query = "DELETE FROM element WHERE element_id = '$element_id'";

    $dbh->do($query);
    $dbh->do($e_query);

    return 1;
}


=item * $category_id = $category->duplicate_check()

This method checks the database to see if any existing site objects possess any
of the same values as the one in memory.  If a duplicate is found, the
category_id of the dupe is returned, otherwise, undef is returned.

=cut

sub duplicate_check {
    my $self = shift;
    my $id = $self->{category_id};
    my $query = <<SQL;
SELECT category_id
FROM category
WHERE dir = ? AND site_id = ?
SQL

    my @params = ($self->{dir}, $self->{site_id});

    # alter query if save() has already been called
    if ($id) {
        $query .=  "AND category_id != ?\n";
        push @params, $id;
    }
    if ($self->{parent_id}) {
        $query .= "AND parent_id = ?";
        push @params, $self->{parent_id};
    }

    my $dbh = dbh();
    my ($category_id) = $dbh->selectrow_array($query, undef, @params);

    return $category_id;
}


=item * @categories = Krang::Category->find( %params )

=item * @categories = Krang::Category->find( category_id => [1, 1, 2, 3, 5] )

=item * @category_ids = Krang::Category->find( ids_only => 1, %params )

=item * $count = Krang::Category->find( count => 1, %params )

Class method that returns an array of category objects, category ids, or a
count.  Case-insensitive sub-string matching can be performed on any valid
field by passing an argument like: "fieldname_like => '%$string%'" (Note: '%'
characters must surround the sub-string).  The valid search fields are:

=over 4

=item * category_id

=item * element_id

=item * dir

=item * parent_id

=item * path

=item * site_id

=back

Additional criteria which affect the search results are:

=over 4

=item * count

If this argument is specified, the method will return a count of the categories
matching the other search criteria provided.

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

=item * order_desc

Specify this option with a value of 'asc' or 'desc' to return the results in
ascending or descending sort order relative to the 'order_by' field

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
      ($ids_only ? 'category_id' : join(", ", grep {$_ ne 'element'}
                                        keys %category_cols));

    # set up WHERE clause and @params, croak unless the args are in
    # CATEGORY_RO or CATEGORY_RW
    my @invalid_cols;
    for my $arg (keys %args) {
        # don't use element
        next if $arg eq 'element';

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
            # set '_old_dir' and '_old_url'
            $row->{_old_dir} = $row->{dir};
            $row->{_old_url} = $row->{url};
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
'category_id' and 'url' will be defined if the call is successful. If the
'dir' field has changed since the last save, the 'url' field will be
reconstructed and update_child_url() is called to update the urls underneath
the present object.

The method croaks if the save would result in a duplicate category object (i.e.
if the object has the same path or url as another object).  It also croaks if
its database query affects no rows in the database.

=cut

sub save {
    my $self = shift;
    my $id = $self->{category_id} || '';
    my @lookup_fields = qw/dir url/;
    my @save_fields = grep {$_ ne 'category_id' && $_ ne 'element'}
      keys %category_cols;

    # check for duplicates
    my $category_id = $self->duplicate_check();
    croak(__PACKAGE__ . "->save(): 'dir' is a duplicate of category " .
          "'$category_id'.")
      if defined $category_id;

    # save element, get id back
    my ($element) = $self->{element};
    $element->save();
    $self->{element_id} = $element->element_id();

    my $query;
    my $dbh = dbh();

    # the object has already been saved once if $id
    if ($id) {
        # recalculate url if we have a new dir...
        if ($self->{dir} ne $self->{_old_dir}) {
            if ($self->{_old_dir} eq '/') {
                $self->{url} = $self->{url} . $self->{dir};
            } else {
                $self->{url} =~ s|\Q$self->{_old_dir}\E$|$self->{dir}|;
            }
        }
        $query = "UPDATE category SET " .
          join(", ", map {"$_ = ?"} @save_fields) .
            " WHERE category_id = ?";
    } else {
        # calculate url...
        my $param;
        if ($self->{parent_id}) {
            $query = "SELECT url FROM category WHERE category_id = ?";
            $param = $self->{parent_id};
        } else {
            $query = "SELECT url FROM site WHERE site_id = ?";
            $param = $self->{site_id};
        }
        my ($url) = $dbh->selectrow_array($query, undef, ($param));
        $self->{url} = join('/', $url, $self->{dir});

        # prevent '//' string from being stored...
        $self->{url} =~ s|//|/|g;

        # set _old_url
        $self->{_old_url} = $self->{url};

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

    # update child URLs if url has changed
    if ($id && ($self->{url} ne $self->{_old_url})) {
        $self->update_child_urls();
        $self->{_old_dir} = $self->{dir};
        $self->{_old_url} = $self->{url};
    }

    return $self;
}


=item * $success = $category->update_child_urls()

Instance method that will search through the category, media, story, and
template tables and replaces all occurrences of the category's old dir with the
new one.

=cut

sub update_child_urls {
    my $self = shift;
    my $id = $self->{category_id};
    my (%ids, $row);
    my $dbh = dbh();

    # build hash of category_id and old urls
    my $query = <<SQL;
SELECT category_id, url
FROM category
WHERE site_id = '$self->{site_id}' AND category_id != '$self->{category_id}'
      AND url LIKE ?
SQL

    my $sth = $dbh->prepare($query);
    $sth->execute(($self->{_old_url} . '%'));
    $sth->bind_columns(\(@$row{@{$sth->{NAME_lc}}}));
    while($sth->fetch()) {
        $ids{$row->{category_id}} = $row->{url};
    }
    $sth->finish();

    $query = <<SQL;
UPDATE category
SET url = ?
WHERE category_id = ?
SQL

    $sth = $dbh->prepare($query);

    for (keys %ids) {
        (my $url = $ids{$_}) =~  s|^\Q$self->{_old_url}\E|$self->{url}|;
        $sth->execute(($url, $_));
    }

    # update the 'url's of media, stories, and templates
    # only implemented in template so far...
    $query = "SELECT %s_id, url FROM %s WHERE category_id = $id";

    # lock the table to prevent checkouts while we're doing the update
    eval {
        for my $table(qw/template/) { #media story_category
            $dbh->do("LOCK TABLES $table WRITE");

            my ($id, $url);
            $sth = $dbh->prepare(sprintf($query, $table, $table));
            $sth->execute();
            $sth->bind_columns(\$id, \$url);
            $ids{$id} = $url while $sth->fetchrow_arrayref();
            $sth->finish();

            $sth = $dbh->prepare("UPDATE $table SET url = ? WHERE " .
                                 "$table\_id = ?");
            for (keys %ids) {
                ($url = $ids{$_}) =~ s|^\Q$self->{_old_url}\E|$self->{url}|;
                $sth->execute(($url, $_));
            }
            $sth->finish();

            $dbh->do("UNLOCK TABLES");
        }
    };

    if (my $eval_err = $@) {
        # make sure to unlock the table
        $dbh->do("UNLOCK TABLES");
        croak(__PACKAGE__ . "->update_child_urls(): $@");
    }

    return 1;
}


=back

=head1 TO DO

 * Optimize performance of update_child_urls(); this operation may potentially
   be run on 1 million+ objects.

=head1 SEE ALSO

L<Krang>, L<Krang::DB>, L<Krang::Element>

=cut


my $quip = <<END;
Life's but a walking shadow, a poor player
That struts and frets his hour upon the stage
And then is heard no more: it is a tale
Told by an idiot, full of sound and fury,
Signifying nothing.

--Shakespeare (Macbeth Act V, Scene 5)
END
