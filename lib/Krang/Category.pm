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

  # setters
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

N.B. Categories must be associated with a site via the 'site_id' constructor
arg or a 'parent_id' equal to the category idea of a valid object must be
passed.  Once the Category object is saved, 'parent_id' cannot be altered.

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
use Exception::Class
  ('Krang::Category::Dependent' => {fields => 'dependents'},
   'Krang::Category::DuplicateURL' => {fields => 'category_id'},
   'Krang::Category::RootDeletion');
use File::Spec;
use Storable qw(freeze thaw);

# Internal Modules
###################
use Krang::DB qw(dbh);
use Krang::Element;
use Krang::Media;
use Krang::Story;
use Krang::Template;
use Krang::Group;

#
# Package Variables
####################
# Constants
############
# Read-only fields
use constant CATEGORY_RO => qw(category_id
			       element_id
			       parent_id
			       url);

# Read-write fields
use constant CATEGORY_RW => qw(dir
			       element
			       site_id);

# Globals
##########

# Lexicals
###########
my %category_args = map {$_ => 1} qw(dir parent_id site_id);
my %category_cols = map {$_ => 1} CATEGORY_RO, CATEGORY_RW, 'parent_id';

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

=item * parent_id (read-only)

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

=item * preview_url (read-onlu)

The preview URL for this category

=cut

sub preview_url {
    my $self = shift;
    croak "illegal attempt to set readonly attribute 'preview_url'.\n"
      if @_;
    my $url = $self->url;
    my $site = $self->site;
    my $site_url = $site->url;
    my $site_preview_url = $site->preview_url;
    $url =~ s/^\Q$site_url\E/$site_preview_url/;

    return $url;
}


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

If the category being created is a subcategory (e.g. it has a C<parent_id>), the value of C<dir> should be the subdirectory itself, B<NOT> the full directory path - that will be handled internally by Krang::Category.

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

    # extract 'parent_id' if any
    $self->{parent_id} = delete $args{parent_id} if exists $args{parent_id};

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
    $self->{element} = Krang::Element->new(class => 'category',
                                           object => $self);
    $self->{element_id} = $self->{element}->element_id();

    return $self;
}


=item * $success = $category->delete()

=item * $success = Krang::Category->delete( $category_id )

Instance or class method that deletes the given category and its associated
element from the database.  It returns '1' following a successful deletion.

This method's underlying call to dependent_check() may result in a
Krang::Category::Dependency exception if an object in the system is found that
relies upon the Category in question.

N.B. - If this call attempts to remove a root category (i.e. a category whose
'dir' field eq '/') and the call is not made by Krang::Site, a
Krang::Category::RootDeletion exception will be thrown.  This behavior exists
because the deletion of a root category results in a disabled Site.  The user
would be unable to add categories to this given Site and to correct this he
would have to know that he must add another root category before and
subcategories could again be added to the Site.  This behavior is preferable to
requiring so comprehensive an understanding of the API by the user :).

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->{category_id};
    ($self) = Krang::Category->find(category_id => $id)
      unless (ref $self && $self->isa('Krang::Category'));

    # Throw RootDeletion exception unless called by Krang::Site
    if ($self->{dir} eq '/') {
        Krang::Category::RootDeletion->throw(message => 'Root categories ' .
                                             'can only be removed by ' .
                                             'deleting their Site object')
            unless (caller)[0] eq 'Krang::Site';
    }

    # throws dependent exception if one exists
    $self->dependent_check();

    # Remove from permissions
    Krang::Group->delete_category_permissions($self);

    # delete element
    $self->element()->delete();

    # delete category
    my $query = "DELETE FROM category WHERE category_id = ?";
    my $dbh = dbh();
    $dbh->do($query, undef, $id);

    # verify deletion was successful
    return Krang::Category->find(category_id => $id) ? 0 : 1;
}


=item * $category->dependent_check()

=item * Krang::Category->dependent_check(category_id => $category_id )

Class or instance method that should be called before attempting to delete the
given category object.  If dependents are found a Krang::Category::Duplicate
exception is thrown, otherwise, 0 is returned.

Krang::Category::Duplicate exceptions have one field 'dependents' that
contains a hashref of the classnames and ids of the objects which depend upon
the given category object.  You might want to handle the exception thusly:

 eval {$category->dependent_check()};
 if ($@ and $@->isa('Krang::Category::Dependent')) {
     my $dependents = $@->dependents();
     $dependents = join("\n\t", map{"$_: [" .
       join(",", @{$dependents->{$_}}) .
       "]"} keys %$dependents);
     croak("The following object classes and ids rely upon this " .
	   "category:\n\t$dependents);
 }

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
    for my $type(qw/Media Story Template/) {
        no strict 'subs';
        for ("Krang::$type"->find(category_id => $id)) {
            my $field = lc $type . "_id";
            push @{$info{lc($type)}}, $_->$field;
            $dependents++;
        }
    }

    Krang::Category::Dependent->throw(message => "Category cannot be deleted.".
                                      "  Objects depend on its exsitence.",
                                      dependents => \%info)
        if $dependents;

    return $dependents;
}


=item * $category->duplicate_check()

This method checks the database to see if an existing category already possess
the same values in its 'url' as the object in memory.  If a duplicate is found,
a Krang::Category::DuplicateURL exception is thrown, otherwise, 0 is returned.

Krang::Category::DuplicateURL excpetions have a single field 'category_id' that
indicates the id of the Category object that would be duplicated:

 eval {$self->duplicate_check()};
 if ($@ and $@->isa('Krang::Category::DuplicateURL')) {
     croak("The 'url' of this category duplicates that of category id: " .
       $@->category_id\n");
 }

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
    my ($category_id) = $dbh->selectrow_array($query, undef, @params) || 0;

    # throw exception
    Krang::Category::DuplicateURL->throw(message => 'Duplicate URL',
                                         category_id => $category_id)
        if $category_id;

    # otherwise return 0
    return $category_id;
}

=item * @categories = Krang::Category->ancestors()

=item * @category_ids = Krang::Category->ancestors( ids_only => 1 )

Will return array of Krang::Category objects or category_ids of parents and
parents of parents etc

=cut

sub ancestors {
    my $self = shift;
    my %args = @_;
    my $ids_only = $args{ids_only} ? 1 : 0;
    my @ancestors;
    my $parent_found = $self->parent();
    return if not $parent_found;

    my $id_or_obj = $ids_only ? $parent_found->category_id : $parent_found;
    push @ancestors, $id_or_obj;

    while ($parent_found) {
        $parent_found = $parent_found->parent();

        if ($parent_found) {
            $id_or_obj = $ids_only ? $parent_found->category_id :
              $parent_found;
            push @ancestors, $id_or_obj;
        }
    }
    return @ancestors;
}


=item * @categories = Krang::Category->descendants()

=item * @category_ids = Krang::Category->descendants( ids_only => 1 )



=cut

sub descendants {
    my $self = shift;
    my %args = @_;
    my $ids_only = $args{ids_only} ? 1 : 0;
    my @descendants;
    my @children_found = $self->children;

    return if not $children_found[0];

    $ids_only ? (push @descendants, (map { $_->category_id } @children_found)) :
      (push @descendants, @children_found);

    foreach my $child (@children_found) {
        my @c_cs = $child->children();
        $ids_only ? (push @descendants, (map { $_->category_id } @c_cs) ) :
          (push @descendants, @c_cs);
        push @children_found, @c_cs;
    }
    return @descendants;
}


=item * @categories = Krang::Category->children()

=item * @category_ids = Krang::Category->children( ids_only => 1 )

Returns array of Krang::Category objects or category_ids of immediate childen.
Convenience method to find().

=cut

sub children {
    my $self = shift;
    my %args = @_;
    my $ids_only = $args{ids_only} ? 1 : 0;

    return $ids_only ?
      Krang::Category->find(parent_id => $self->category_id, ids_only => 1) :
          Krang::Category->find(parent_id => $self->category_id);
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
            # set '_old_dir' and '_old_url'
            $row->{_old_dir} = $row->{dir};
            $row->{_old_url} = $row->{url};
            push @categories, bless({%$row}, $self);

            # load 'element'
            ($categories[-1]->{element}) =
              Krang::Element->load(element_id => $row->{element_id}, 
                                   object     => $categories[-1]);
            $categories[-1]->{element_id} =
              $categories[-1]->{element}->element_id;
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
    my @save_fields =
      grep {$_ ne 'category_id' && $_ ne 'element' && $_ ne 'parent_id'}
        keys %category_cols;

    # set flag if url must change; only applies to objects after first save...
    my $new_url = ($id && ($self->{dir} ne $self->{_old_dir})) ? 1 : 0;

    # check for duplicates: a DuplicateURL exception will be thrown if a
    # duplicate is found
    $self->duplicate_check();

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
            $self->{url} =~ s|\Q$self->{_old_dir}\E/?$||
              unless $self->{_old_dir} eq '/';
            $self->{url} = _build_url($self->{url}, $self->{dir});
        }
        $query = "UPDATE category SET " .
          join(", ", map {"$_ = ?"} @save_fields) .
            " WHERE category_id = ?";
    } else {
        # set 'parent_id' on initial save
        push @save_fields, 'parent_id';
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

    unless ($id) {
        # Set category_id directly in object
        $self->{category_id} = $dbh->{mysql_insertid};

        # Make sure category permissions (and cache) are added for this category
        Krang::Group->add_category_permissions($self);
    }

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
sub _build_url {
    (my $url = join('/', @_)) =~ s|/+|/|g;
    $url .= '/' unless $url =~ m|/$|;
    return $url;
}

=item C<< $category->serialize_xml(writer => $writer, set => $set) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self, %args) = @_;
    my ($writer, $set) = @args{qw(writer set)};
    local $_;

    # open up <category> linked to schema/category.xsd
    $writer->startTag('category',
                      "xmlns:xsi" => 
                        "http://www.w3.org/2001/XMLSchema-instance",
                      "xsi:noNamespaceSchemaLocation" =>
                        'category.xsd');

    $writer->dataElement(category_id   => $self->category_id);
    $writer->dataElement(site_id => $self->site_id);
    if ($self->parent_id) {
        $writer->dataElement(parent_id => $self->parent_id);
        $set->add(object => $self->parent, from => $self);
    }
    $set->add(object => $self->site, from => $self);

    # basic fields
    $writer->dataElement(dir => $self->dir);
    $writer->dataElement(url => $self->url);

    # serialize elements
    $self->element->serialize_xml(writer => $writer,
                                  set    => $set);
    $writer->endTag('category');
}

=item C<< $category = Krang::Category->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML.  See Krang::DataSet for details.

If an incoming category has the same URL as an existing category then
an update will occur.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set, $no_update) = @args{qw(xml set no_update)};

    # parse it up
    my $data = Krang::XML->simple(xml           => $xml, 
                                  suppressempty => 1,
                                  forcearray    => ['element', 'data']);
    

    # is there an existing category with this URL?
    my ($dup) = Krang::Category->find(url => $data->{url});
    if ($dup) {
        Krang::DataSet::DeserializationFailed->throw(
            message => "A category with the URL ".
                       "$data->{url} already exists and ".
                       "no_update is set.")
            if $no_update;

        # deserialize elements for update
        my $element = Krang::Element->deserialize_xml(data => 
                                                        $data->{element}[0],
                                                      set       => $set,
                                                      no_update => $no_update,
                                                      object    => $dup);
        $dup->{element}->delete if $dup->{element};
        $dup->{element} = $element;
        $dup->{element_id} = $element->element_id;
        $dup->save();
        
        return $dup;
    }

    # get import site_id
    my ($site_id, $parent_id);
    if ($data->{parent_id}) {
        # get import parent_id
        $parent_id = $set->map_id(class => "Krang::Category",
                                  id    => $data->{parent_id});
    } else {
        # get site_id for root category
        $site_id = $set->map_id(class => "Krang::Site",
                                id    => $data->{site_id});
    }

    # create a new category
    my $cat = Krang::Category->new(
                                   ($parent_id ? 
                                    (parent_id => $parent_id) : ()),
                                   ($site_id   ? 
                                    (site_id   => $site_id)   : ()),
                                   dir => $data->{dir},
                                  );
    # deserialize elements
    my $element = Krang::Element->deserialize_xml(data => $data->{element}[0],
                                                  set       => $set,
                                                  no_update => $no_update,
                                                  object    => $cat);
    $cat->{element} = $element;
    $cat->{element_id} = $element->element_id;

    $cat->save();

    return $cat;
}

=item C<< $data = Storable::freeze($category) >>

Serialize a category.  Krang::Category implements STORABLE_freeze() to
ensure this works correctly.

=cut

sub STORABLE_freeze {
    my ($self, $cloning) = @_;
    return if $cloning;

    # make sure element tree is loaded
    $self->element();
    
    # serialize data in $self with Storable
    my $data;
    eval { $data = freeze({%$self}) };
    croak("Unable to freeze story: $@") if $@;

    return $data;
}

=item C<< $category = Storable::thaw($data) >>

Deserialize a frozen story.  Krang::Category implements STORABLE_thaw()
to ensure this works correctly.

=cut

sub STORABLE_thaw {
    my ($self, $cloning, $data) = @_;

    # FIX: is there a better way to do this?
    # Krang::Element::STORABLE_thaw needs a reference to the story in
    # order to thaw the element tree, but thaw() doesn't let you pass
    # extra arguments.
    local $Krang::Element::THAWING_OBJECT = $self;

    # retrieve object
    eval { %$self = %{thaw($data)} };
    croak("Unable to thaw story: $@") if $@;

    return $self;
}

=head1 TO DO

 * Optimize performance of update_child_urls(); this operation may
   potentially be run on 1 million+ objects.

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
