package Krang::Group;
use strict;
use warnings;


=head1 NAME

Krang::Group - Interface to manage Krang permissions


=head1 SYNOPSIS

  # Include the library
  use Krang::Group;


  # Create a new group
  my $group = Krang::Group->new( name => 'Car Editors',
                                 categories => { 1 => 'read-only', 
                                                 2 => 'edit', 
                                                 23 => 'hide' },
                                 desks      => { 1 => 'read-only', 
                                                 2 => 'edit', 
                                                 23 => 'hide' },
                                 may_publish         => 1,
                                 admin_users         => 1,
                                 admin_users_limited => 1,
                                 admin_groups        => 1,
                                 admin_contribs      => 1,
                                 admin_sites         => 1,
                                 admin_categories    => 1,
                                 admin_jobs          => 1,
                                 admin_desks         => 1,
                                 admin_prefs         => 1,
                                 asset_story         => 'edit',
                                 asset_media         => 'read-only',
                                 asset_template      => 'hide' );


  # Retrieve an existing group by ID
  my ($group) = Krang::Group->find( group_id => 123 );


  # Retrieve multiple existing groups by ID
  my @groups = Krang::Group->find( group_ids => [1, 2, 3] );


  # Find groups by exact name
  my @groups = Krang::Group->find( name => 'Boat Editors' );


  # Find groups by name pattern
  my @groups = Krang::Group->find( name_like => '%editor%' );


  # Save group
  $group->save();


  # Delete group
  $group->delete();


  # Get group ID
  my $group_id = $self->group_id();


  # Accessors/Mutators
  my $name             = $group->name();
  my $may_publish      = $group->may_publish();
  my $admin_users      = $group->admin_users();
  my $admin_users_limited = $group->admin_users_limited();
  my $admin_groups     = $group->admin_groups();
  my $admin_contribs   = $group->admin_contribs();
  my $admin_sites      = $group->admin_sites();
  my $admin_categories = $group->admin_categories();
  my $admin_jobs       = $group->admin_jobs();
  my $admin_desks      = $group->admin_desks();
  my $admin_prefs      = $group->admin_prefs();
  my $asset_story      = $group->asset_story();
  my $asset_media      = $group->asset_media();
  my $asset_template   = $group->asset_template();
  my %categories       = $group->categories();
  my %desks            = $group->desks();


  # Category permissions cache management
  Krang::Group->add_catagory_cache($category);
  Krang::Group->delete_catagory_cache($category);
  Krang::Group->rebuild_catagory_cache();


=head1 DESCRIPTION

Krang::Group provides access to manipulate Krang's permission groups.
These groups control authorization within Krang as documented in the file 
F<krang/docs/permissions.pod>.


=head1 INTERFACE

The following methods are provided by Krang::Group.

=over 4

=cut


# Required modules
use Carp;
use Krang::DB qw(dbh);
use Krang::Category;
use Krang::Log qw(debug);
use Krang::Desk;
use Krang::Category;


# Exceptions
use Exception::Class ( 'Krang::Group::DuplicateName' => { fields => [ 'group_id' ] } );


# Database fields in table permission_group, asidde from group_id
use constant FIELDS => qw( name
                           may_publish
                           admin_users
                           admin_users_limited
                           admin_groups
                           admin_contribs
                           admin_sites
                           admin_categories
                           admin_jobs
                           admin_desks
                           admin_prefs
                           asset_story
                           asset_media
                           asset_template );

# Constructor/Accessor/Mutator setup
use Krang::MethodMaker ( new_with_init => 'new',
                         new_hash_init => 'hash_init',
                         get => [ "group_id" ],
                         get_set => [ FIELDS ],
                         hash => [ qw( categories
                                       desks ) ] );


=item new()

  my $group = Krang::Group->new();

This method returns a new Krang::Group object.  You may pass a hash
into new() containing initial values for the object properties.  These
properties are:

  * name               - Name of this group
  * asset_story        - Story asset security level
  * asset_media        - Media asset security level
  * asset_template     - Template asset security level
  * categories (hash)  - Map category ID to security level
  * desks (hash)       - Map desk ID to security level

Security levels may be "edit", "read-only", or "hide".

In addition to these properties, the following properties may be
specified using Boolean (1 or 0) values:

  * may_publish
  * admin_users
  * admin_users_limited
  * admin_groups
  * admin_contribs
  * admin_sites
  * admin_categories
  * admin_jobs
  * admin_desks
  * admin_prefs

=cut

sub init {
    my $self = shift;
    my %args = ( @_ );

    # Get list of root categoies and all desks, for permissions
    my @root_cats = Krang::Category->find(ids_only=>1, parent_id=>undef);
    my @all_desks = ();   # NOT YET IMPLEMENTED -- Krang::Desk->find(ids_only=>1)

    # Set up default values
    my %defaults = (
                    name => "",
                    may_publish         => 0,
                    admin_users         => 0,
                    admin_users_limited => 0,
                    admin_groups        => 0,
                    admin_contribs      => 0,
                    admin_sites         => 0,
                    admin_categories    => 0,
                    admin_jobs          => 0,
                    admin_desks         => 0,
                    admin_prefs         => 0,
                    asset_story         => 'edit',
                    asset_media         => 'edit',
                    asset_template      => 'edit',
                    categories          => { map { $_ => "edit" } @root_cats },
                    desks               => { map { $_ => "edit" } @all_desks },
                   );

    # finish the object
    $self->hash_init(%defaults, %args);

    # Set default group_id
    $self->{group_id} = 0;

    return $self;
}


=item find()

  my @groups = Krang::Group->find();

Retrieve Krang::Group objects from database based on a search
specification.  Searches are specified by passing a hash to find()
with search fields as keys and search terms as the values of those keys.
For example, the following would retrieve all groups with the 
word "admin" in the group name:

  my @groups = Krang::Group->find(name_like => '%admin%');

Search terms may be combined to further narrow the result set.  For 
example, the following will limit the above search to groups
whose IDs are in an explicit list:

  my @groups = Krang::Group->find( name_like => '%admin%',
                                   group_ids => [1, 5, 10, 34] );

The following search fields are recognized by Krang::Group->find():

  * simple_search  - A scalar string, matches to name
  * group_id       - Retrieve a specific group by ID
  * group_ids      - Array reference of group_ids which should be retrieved
  * name           - Exactly match the group name
  * name_like      - SQL LIKE-match the group name


The find() method provides meta terms to control how the data should 
be returned:

  * count          - Causes find() to return the number of matches instead of 
                     the actual objects.
  * ids_only       - Causes find() to return the IDs of the matching groups
                     instead of the instantiated group objects.
  * order_by       - The group field by which the found objects should be 
                     sorted.  Defaults to "name".
  * order_desc     - Results will be sorted in descending order if this is
                     set to "1", ascending if "0".  Defaults to "0".
  * limit          - The number of objects to be returned.  Defaults to all.
  * offset         - The index into the result set at which objects should be
                     returned.  Defaults to "0" -- the first record.


=cut

sub find {
    my $self = shift;
    my %args = @_;


    # Check for invalid args and croak() if any
    my @valid_find_params = qw(
                               order_by
                               order_desc
                               limit
                               offset
                               count
                               ids_only

                               simple_search
                               group_id
                               group_ids
                               name
                               name_like
                              );

    foreach my $arg (keys(%args)) {
        croak ("Invalid find arg '$arg'")
          unless (grep { $arg eq $_ } @valid_find_params);
    }

    # For SQL query
    my $order_by  = delete $args{order_by} || 'name';
    my $order_dir = delete $args{order_desc} ? 'DESC' : 'ASC';
    my $limit     = delete $args{limit}    || 0;
    my $offset    = delete $args{offset}   || 0;
    my $count     = delete $args{count}    || 0;
    my $ids_only  = delete $args{ids_only} || 0;

    # check for invalid argument sets
    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.")
      if $count and $ids_only;

    my @sql_wheres = ();
    my @sql_where_data = ();

    #
    # Build search query
    #

    # simple_search: like searches on name
    if (my $search = $args{simple_search}) {
        my @words = split(/\W+/, $search);
        my @like_words = map { "\%$_\%" } @words;
        push(@sql_wheres, (map { "name LIKE ?" } @like_words) );
        push(@sql_where_data, @like_words);
    }


    # group_id
    if (my $search = $args{group_id}) {
        push(@sql_wheres, "group_id = ?" );
        push(@sql_where_data, $search);
    }


    # group_ids
    if (my $search = $args{group_ids}) {
        croak ("group_ids must be an array ref")
          unless ($search and (ref($search) eq 'ARRAY'));
        croak ("group_ids array ref may only contain numeric IDs")
          if (grep { $_ =~ /\D/ } @$search);
        my $group_ids_str = join(",", @$search);
        push(@sql_wheres, "group_id IN ($group_ids_str)" );
    }


    # name
    if (my $search = $args{name}) {
        push(@sql_wheres, "name = ?" );
        push(@sql_where_data, $search);
    }


    # name_like
    if (my $search = $args{name_like}) {
        $search =~ s/\W+/%/g;
        push(@sql_wheres, "name LIKE ?" );
        push(@sql_where_data, "$search");
    }


    #
    # Build SQL query
    #

    # Handle order by/dir
    my @order_bys = split(/,/, $order_by);
    my @order_by_dirs = map { "$_ $order_dir" } @order_bys;

    # Build SQL where, order by and limit clauses as string -- same for all situations
    my $sql_from_where_str = "from permission_group ";
    $sql_from_where_str .= "where ". join(" and ", @sql_wheres) ." "  if (@sql_wheres);
    $sql_from_where_str .= "order by ". join(",", @order_by_dirs) ." ";
    $sql_from_where_str .= "limit $offset,$limit"  if ($limit);

    # Build select list and run SQL, return results
    my $dbh = dbh();

    if ($count) {
        # Return count(*)
        my $sql = "select count(*) $sql_from_where_str";
        debug_sql($sql, \@sql_where_data);

        my ($group_count) = $dbh->selectrow_array($sql, {RaiseError=>1}, @sql_where_data);
        return $group_count;


    } elsif ($ids_only) {
        # Return group_ids
        my $sql = "select group_id $sql_from_where_str";
        debug_sql($sql, \@sql_where_data);

        my $sth = $dbh->prepare($sql);
        $sth->execute(@sql_where_data);
        my @group_ids = ();
        while (my ($group_id) = $sth->fetchrow_array()) {
            push(@group_ids, $group_id);
        };
        $sth->finish();
        return @group_ids;


    } else {
        # Return objects
        my $sql_fields = join(",", ("group_id", FIELDS) );
        my $sql = "select $sql_fields $sql_from_where_str";
        debug_sql($sql, \@sql_where_data);

        my $sth = $dbh->prepare($sql);
        $sth->execute(@sql_where_data);
        my @groups = ();
        while (my $group_data = $sth->fetchrow_hashref) {
            push(@groups, $self->new_from_db($group_data));
        };
        $sth->finish();
        return @groups;

    }
}


=item save();

  $group->save();

Save the group object to the database.  If this is a new group object
it will be inserted into the database and group_id will be defined.

If another existing group has the same name as the group you're trying
to save, an exception will be thrown:  Krang::Group::DuplicateName

In all cases, the group object's configured category and desk 
permissions will be checked for validity and sanitized if necessary.

For categories, this means that if a root category is not specified
in the categories() hash, it will be silently created with "edit"
permissions.

In the case of desks, missing desks will be created 
with "edit" permissions.

N.B.:  No effort is made to assure that a specified category or desk 
actually exists.  An invalid category or desk will be dutifully
added to the permissions table.


=cut

sub save {
    my $self = shift;

    # Validate object or throw up
    $self->validate_group();

    # Insert if this is a new group
    $self->insert_new_group() unless ($self->group_id);

    my $group_id = $self->group_id();

    # Update group object primary fields in database
    my $update_sql = "update permission_group set ";
    $update_sql .= join(", ", map { "$_=?" } FIELDS);
    $update_sql .= " where group_id=?";

    my @update_data = ( map { $self->$_ } FIELDS );
    push(@update_data, $group_id);

    debug_sql($update_sql, \@update_data);

    my $dbh = dbh();
    $dbh->do($update_sql, {RaiseError=>1}, @update_data);

    # Sanitize categories: Make sure all root categories are specified
    my @root_cats = Krang::Category->find(ids_only=>1, parent_id=>undef);
    my %categories = $self->categories();
    foreach my $cat (@root_cats) {
        $categories{$cat} = "edit" unless (exists($categories{$cat}));
    }

    # Blow away all category perms in database and re-build
    $dbh->do( "delete from category_group_permission where group_id=?",
              {RaiseError=>1}, $group_id );
    my $cats_sql = "insert into category_group_permission (group_id,category_id,permission_type) values (?,?,?)";
    my $cats_sth = $dbh->prepare($cats_sql);
    while (my ($category_id, $permission_type) = each(%categories)) {
        $cats_sth->execute($group_id, $category_id, $permission_type);
    }

    # Sanitize desks: Make sure all desks are specified
    my @all_desks = ();   # NOT YET IMPLEMENTED -- Krang::Desk->find(ids_only=>1)
    my %desks = $self->desks();
    foreach my $desk (@all_desks) {
        $desks{$desk} = "edit" unless (exists($desks{$desk}));
    }

    # Blow away all desk perms in database and re-build
    $dbh->do( "delete from desk_group_permission where group_id=?",
              {RaiseError=>1}, $group_id );
    my $desks_sql = "insert into desk_group_permission (group_id,desk_id,permission_type) values (?,?,?)";
    my $desks_sth = $dbh->prepare($desks_sql);
    while (my ($desk_id, $permission_type) = each(%desks)) {
        $desks_sth->execute($group_id, $desk_id, $permission_type);
    }

}


=item delete()

  $group->delete();

Remove a Krang::Group from the system.

=cut

sub delete {
    my $self = shift;

    my $group_id = $self->group_id();

    # Unsaved group?  Bail right away
    return unless ($group_id);

    # Blow away data
    my $dbh = dbh();
    my @delete_from_tables = qw( category_group_permission
                                 category_group_permission_cache
                                 desk_group_permission
                                 usr_user_group
                                 permission_group );

    foreach my $table (@delete_from_tables) {
        $dbh->do( "delete from $table where group_id=?",
                  {RaiseError=>1}, $group_id );
    }
}


=item add_catagory_cache()

  Krang::Group->add_catagory_cache($category);

Given a particular category object, update the category_group_permission_cache
table to add this category for all groups.

=cut

sub add_catagory_cache {
    my $self = shift;
    my ($category) = @_;

    croak ("No category provided") unless ($category && ref($category));

    my $dbh = dbh();

    # Iterate through each group

}



=item delete_catagory_cache()

  Krang::Group->delete_catagory_cache($category_id);

Given a particular category ID, update the category_group_permission_cache
table to delete this category for all groups.

=cut

sub delete_catagory_cache {
    my $self = shift;
    my ($category_id) = @_;

    croak ("Invalid category_id '$category_id'") unless ($category_id and $category_id =~ /^\d+$/);

    my $dbh = dbh();
    $dbh->do( "delete from category_group_permission_cache where category_id=?",
              {RaiseError=>1}, $category_id );
}



=item rebuild_catagory_cache()

  Krang::Group->rebuild_catagory_cache();

This class method will clear the table category_group_permission_cache 
and rebuild it from the category_group_permission table.  This logically 
iterates through each group and applying the permissions for each category 
according to the configuration.

Permissions for a particular category are applicable to all descendant
categories.  In lieu of a specific disposition for a particular category
(as is the case if a group does not specify access for a site), permissions
will default to "edit".  IOW, 


=cut

sub rebuild_catagory_cache {
    my $self = shift;

    my $dbh = dbh();

    # Clear cache table
    $dbh->do( "delete from category_group_permission_cache", {RaiseError=>1});
}



###########################
####  PRIVATE METHODS  ####
###########################

# Verify that the Krang::Object is valid prior to saving
# Throw exceptions if not.
sub validate_group {
    my $self = shift;

    # Are permissions valid?
    my @valid_levels = qw(edit read-only hide);

    # Check assets
    my @assets = qw(story media template);
    foreach my $asset (@assets) {
        my $ass_method = "asset_$asset";
        my $level = $self->$ass_method;
        croak ("Invalid $ass_method security level '$level'") unless (grep { $level eq $_ } @valid_levels);
    }

    # Check categories
    my %categories = $self->categories;
    while (my ($cat, $level) = each(%categories)) {
        croak ("Invalid security level '$level' for category_id '$cat'")
          unless (grep { $level eq $_ } @valid_levels);
    }

    # Check desks
    my %desks = $self->desks;
    while (my ($desk, $level) = each(%desks)) {
        croak ("Invalid security level '$level' for desk_id '$desk'")
          unless (grep { $level eq $_ } @valid_levels);
    }

    # Is the name unique?
    my $group_id = $self->group_id();
    my $name = $self->name();

    my $dbh = dbh();
    my $is_dup_sql = "select group_id from permission_group where name = ? and group_id != ?";
    my ($dup_id) = $dbh->selectrow_array($is_dup_sql, {RaiseError=>1}, $name, $group_id);

    # If dup, throw exception
    if ($dup_id) {
        Krang::Group::DuplicateName->throw( message => "duplicate group name", group_id => $dup_id );
    }
}


# Create a new database record for group.  Set group_id in object.
sub insert_new_group {
    my $self = shift;

    my $dbh = dbh();
    $dbh->do("insert into permission_group (group_id) values (NULL)") || die($dbh->errstr);

    $self->{group_id} = $dbh->{'mysql_insertid'};
}

# Static function: Given a SQL query and an array ref with
# query data, send query to Krang log.
sub debug_sql {
    my ($query, $param) = ( @_ );

    debug(__PACKAGE__ . "::find() SQL: " . $query);
    debug(__PACKAGE__ . "::find() SQL ARGS: " . join(', ', @$param));
}


# Given a hash ref with data, instantiate a new Krang::Group object
sub new_from_db {
    my $pkg = shift;
    my $group_data = shift;

    my $dbh = dbh();
    my $group_id = $group_data->{group_id};

    # Load categories hash (category_id => security level)
    my $cat_sql = "select category_id, permission_type from category_group_permission where group_id=?";
    my $cat_sth = $dbh->prepare($cat_sql);
    $cat_sth->execute($group_id) || die ($cat_sth->errstr);
    my %categories = ();
    while (my ($category_id, $permission_type) = $cat_sth->fetchrow_array()) {
        $categories{$category_id} = $permission_type;
    }
    $cat_sth->finish();
    $group_data->{categories} = \%categories;

    # Load desks (desk_id => security level)
    my $desk_sql = "select desk_id, permission_type from desk_group_permission where group_id=?";
    my $desk_sth = $dbh->prepare($desk_sql);
    $desk_sth->execute($group_id) || die ($desk_sth->errstr);
    my %desks = ();
    while (my ($desk_id, $permission_type) = $desk_sth->fetchrow_array()) {
        $desks{$desk_id} = $permission_type;
    }
    $desk_sth->finish();
    $group_data->{desks} = \%desks;

    # Bless into object and return
    bless ($group_data, $pkg);
    return $group_data;
}


=back


=head1 AUTHOR

Jesse Erlbaum <jesse@erlbaum.net>

=cut


1;

