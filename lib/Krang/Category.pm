package Krang::Category;

=head1 NAME

Krang::Category - a means to access information on categories

=head1 SYNOPSIS

  use Krang::Category;

  # construct object
  my $category = Krang::Category->new(dir => 'category', # required
			      	      parent_id => 1,
			      	      site_id => 1);

  # 'parent_id' must be present for all categories except '/' 'site_id'
  # must be present for '/'

  # saves object to the DB
  $category->save();

  # getters
  my $element 	= $category->element();
  my $dir 	= $category->dir();
  my $id 	= $category->parent_id();
  my $parent	= $category->parent();
  my $id 	= $category->site_id();
  my $site 	= $category->site();

  my $id 	= $category->category_id(); # undef until after save()
  my $id 	= $category->element_id();  # undef until after save()
  my $url 	= $category->url();	    # undef until after save()

  # setter
  $category->element( $element );
  $category->dir( $some_single_level_dirname );

  # delete the category from the database
  $category->delete();

  # a hash of search parameters
  my %params =
  ( order_desc => 1,		# result ascend unless this flag is set
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
use Krang::Media;
use Krang::Story;
use Krang::Template;

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

=item * element

Element object associated with the given category object belonging to the
special element class 'category'

=item * element_id (read-only)

Id in the element table of this object's element

=item * dir

The display name of the category i.e. '/gophers'

=item * parent_id

Id of this categories parent category, if any

=item * parent

The parent object of the present category if any.

=cut

sub parent {
    my $self = shift;
    return unless $self->{parent_id};
    (Krang::Category->find(category_id => $self->{parent_id}))[0];
}

=item * site_id

Id in the site table of this object's site

=item * site (read-only)

The site object identified by site_id.

=cut

sub site { (Krang::Site->find(site_id => shift->{site_id}))[0] }

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

Either a 'parent_id' or a 'site_id' must be passed but not both.

=back

=cut

# validates arguments passed to new(), see Class::MethodMaker,
# constructs 'url' as it may be needed before save()
# the method croaks if we haven't been provied a 'dir' and 'site_id', if an
# invalid key is found in the hash passed to new(), or if 'dir' contains more
# than '/'
sub init {
    my $self = shift;
    my %args = @_;
    my (@bad_args, @required_args);

    # validate %args
    #################
    for (keys %args) {
        push @bad_args, $_ unless exists $category_args{$_};

    }
    croak(__PACKAGE__ . "->init(): The following constructor args are " .
          "invalid: '" . join("', '", @bad_args) . "'") if @bad_args;

    # check required fields
    croak(__PACKAGE__ . "->init(): Required argument 'dir' not present.")
      unless exists $args{dir};

    croak(__PACKAGE__ . "->init(): 'dir' names can only represent a " .
          "directory directly beneath its parent.")
      if $args{dir} =~ m|^/[^/]+/|;

    # site or parent id must be present
    croak(__PACKAGE__ . "->init(): Either the 'parent_id' or 'site_id' arg " .
          "must be present.")
      unless ($args{site_id} || $args{parent_id});

    $self->hash_init(%args);

    # set '_old_dir' to 'dir' to make changes to 'dir' detectable
    $self->{_old_dir} = $self->{dir};

    # construct 'url'
    #################
    my ($url);
    if ($self->{parent_id}) {
        my ($cat) = Krang::Category->find(category_id => $self->{parent_id});
        croak(__PACKAGE__ . "->init(): No category object found corresponding".
              " to id '$self->{parent_id}'") unless defined $cat;
        $url = $cat->url();
        $self->{site_id} = $cat->site_id;
    } else {
        my ($site) = Krang::Site->find(site_id => $self->{site_id});
        croak(__PACKAGE__ . "->init(): site_id '$self->{site_id}' does not " .
              "correspond to any object in the database.") unless $site;
        $url = $site->url();
    }

    $self->{url} = _build_url($url, $self->{dir});

    # set '_old_url' for use in update_child_urls()
    $self->{_old_url} = $self->{url};

    # define element
    #################
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
    my $id = $self->{category_id};
    ($self) = Krang::Category->find(category_id => $id) if $id;

    # find dependents
    my ($dependents, %dependent_info) = $self->dependent_check();
    if ($dependents) {
        my $info = "\n\t" . join("\n\t",
                                 map{ucfirst($_) . ": " .
                                       join(",", @{$dependent_info{$_}})}
                                 keys %dependent_info);
        croak(__PACKAGE__ . "->delete(): The following objects rely on this " .
              "category:$info");
    }

    # delete element
    $self->element()->delete();

    # delete category
    my $query = "DELETE FROM category WHERE category_id = ?";
    my $dbh = dbh();
    $dbh->do($query, undef, $id);

    return Krang::Category->find(category_id => $id) ? 0 : 1;
}


=item * ($dependents, %info) = $category->dependent_check()

=item * ($dependents, %info) = Krang::Category->dependent_check()

Class or instance method that returns a hash of object types and the ids of
that object type that rely upon the given category.

=cut

sub dependent_check {
    my $self = shift;
    my $id = shift || $self->{category_id};
    my $dependents = 0;
    my (%info, $oid);

    # get dependent categories
    my $query = "SELECT category_id FROM category WHERE parent_id = ?";
    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute($id);
    $sth->bind_col(1, \$oid);
    while ($sth->fetch()) {
        push @{$info{category}}, $oid;
        $dependents++;
    }

    # get other dependencies
    for my $type(qw/Media Template/) { # Story find() not implemented yet
        no strict 'subs';
        for ("Krang::$type"->find(category_id => $id)) {
            my $field = lc $type . "_id";
            push @{$info{lc($type)}}, $_->$field;
            $dependents++;
        }
    }

    return $dependents, %info;
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
WHERE url = ?
SQL

    my @params = ($self->{url});

    # alter query if save() has already been called
    if ($id) {
        $query .=  "AND category_id != ?\n";
        push @params, $id;
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

=item * site_id

=item * url

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

    # grab ascend/descending, limit, and offset args
    my $ascend = delete $args{order_desc} ? 'DESC' : 'ASC';
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
            # load 'element'
            ($row->{element}) =
              Krang::Element->find(element_id => $row->{element_id});
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
if the object has the 'dir' as another object).  It also croaks if its database
query affects no rows in the database.

=cut

sub save {
    my $self = shift;
    my $id = $self->{category_id} || '';
    my @lookup_fields = qw/dir url/;
    my @save_fields = grep {$_ ne 'category_id' && $_ ne 'element'}
      keys %category_cols;

    # set flag if url must change; only applies to objects after first save...
    my $new_url = ($id && ($self->{dir} ne $self->{_old_dir})) ? 1 : 0;

    # check for duplicates
    my $category_id = $self->duplicate_check();
    croak(__PACKAGE__ . "->save(): 'dir' is a duplicate of category id " .
          "'$category_id'")
      if $category_id;

    # save element, get id back
    my ($element) = $self->{element};
    $element->save();
    $self->{element_id} = $element->element_id();

    my $query;
    my $dbh = dbh();

    # the object has already been saved once if $id
    if ($id) {
        # recalculate url if we have a new dir...
        if ($new_url) {
            $self->{url} =~ s|\Q$self->{_old_dir}\E$||
              unless $self->{_old_dir} eq '/';
            $self->{url} = _build_url($self->{url}, $self->{dir});
        }
        $query = "UPDATE category SET " .
          join(", ", map {"$_ = ?"} @save_fields) .
            " WHERE category_id = ?";
    } else {
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
    if ($new_url) {
        $self->update_child_urls();
        $self->{_old_dir} = $self->{dir};
        $self->{_old_url} = $self->{url};
    }

    return $self;
}


=item * $success = $category->update_child_urls()

=item * $success = $category->update_child_urls( $site )

Instance method that will search through the category, media, story, and
template tables and replaces all occurrences of the category's old dir with the
new one.

=cut

sub update_child_urls {
    my $self = shift;
    my $site = shift;
    my $id = $self->{category_id};
    my ($category_id, %ids, @params, $query, $sth, $url);
    my $failures = 0;
    my $dbh = dbh();

    # update 'url' if call was made by site
    if ($site && UNIVERSAL::isa($site, 'Krang::Site')) {
        $self->{url} = _build_url($site->url(), $self->{dir});

        # save new url
        $dbh->do("UPDATE category SET url = ? WHERE category_id = ?",
                 undef, $self->{url}, $id);
    }

    # build hash of category_id and old urls
    $query = <<SQL;
SELECT category_id, url
FROM category
WHERE parent_id = ?
SQL

    $sth = $dbh->prepare($query);
    $sth->execute($id);
    $sth->bind_columns(\$category_id, \$url);
    $ids{$category_id} = $url while $sth->fetch();

    $query = <<SQL;
UPDATE category
SET url = ?
WHERE category_id = ?
SQL

    $sth = $dbh->prepare($query);

    # update category 'url's
    for (sort keys %ids) {
        (my $url = $ids{$_}) =~  s|^\Q$self->{_old_url}\E|$self->{url}|;
        $sth->execute(($url, $_));
    }

    # update the 'url's of media, stories, and templates
    # only implemented in Krang::Template so far...
    for (qw/Template/) { # Media Story
        no strict 'subs';
        for my $obj("Krang::$_"->find(category_id => $id)) {
            $obj->update_url($self->{url});
            $obj->save();
            $failures++ unless $obj->url =~ /$self->{url}/;
        }
    }

    if (keys %ids) {
        for (Krang::Category->find(category_id => [keys %ids])) {
            $failures++ unless $_->url =~ /^$self->{url}/;
        }
    }

    return $failures ? 0 : 1;
}


# constructs a url by joining parts by '/'
sub _build_url { (my $url = join('/', @_)) =~ s|/+|/|g; return $url; }

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
