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
                                 may_checkin_all     => 1,
                                 admin_users         => 1,
                                 admin_users_limited => 1,
                                 admin_groups        => 1,
                                 admin_contribs      => 1,
                                 admin_sites         => 1,
                                 admin_categories    => 1,
                                 admin_jobs          => 1,
                                 admin_desks         => 1,
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
  my $may_checkin_all  = $group->may_checkin_all();
  my $admin_users      = $group->admin_users();
  my $admin_users_limited = $group->admin_users_limited();
  my $admin_groups     = $group->admin_groups();
  my $admin_contribs   = $group->admin_contribs();
  my $admin_sites      = $group->admin_sites();
  my $admin_categories = $group->admin_categories();
  my $admin_jobs       = $group->admin_jobs();
  my $admin_desks      = $group->admin_desks();
  my $asset_story      = $group->asset_story();
  my $asset_media      = $group->asset_media();
  my $asset_template   = $group->asset_template();
  my %categories       = $group->categories();
  my %desks            = $group->desks();


  # Category permissions cache management
  Krang::Group->add_category_permissions($category);
  Krang::Group->delete_category_permissions($category);
  Krang::Group->rebuild_category_cache();

  # Krang::Desk permission management
  Krang::Group->add_desk_permissions($desk);
  Krang::Group->delete_desk_permissions($desk);

  # Evaluate permissions for the currently logged-in user
  my %desk_perms = Krang::Group->user_desk_permissions();
  my %asset_perms = Krang::Group->user_asset_permissions();
  my %admin_perms = Krang::Group->user_admin_permissions();


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


# Database fields in table group_permission, asidde from group_id
use constant FIELDS => qw( name
                           may_publish
                           may_checkin_all
                           admin_users
                           admin_users_limited
                           admin_groups
                           admin_contribs
                           admin_sites
                           admin_categories
                           admin_jobs
                           admin_desks
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
  * may_checkin_all
  * admin_users
  * admin_users_limited
  * admin_groups
  * admin_contribs
  * admin_sites
  * admin_categories
  * admin_jobs
  * admin_desks

=cut

sub init {
    my $self = shift;
    my %args = ( @_ );

    # Set up default values
    my %defaults = (
                    name => "",
                    may_publish         => 0,
                    may_checkin_all     => 0,
                    admin_users         => 0,
                    admin_users_limited => 0,
                    admin_groups        => 0,
                    admin_contribs      => 0,
                    admin_sites         => 0,
                    admin_categories    => 0,
                    admin_jobs          => 0,
                    admin_desks         => 0,
                    asset_story         => 'edit',
                    asset_media         => 'edit',
                    asset_template      => 'edit',
                   );

    # Set up defaults for category and desk permissions
    my @root_cats = Krang::Category->find(ids_only=>1, parent_id=>undef);
    my %categories = ( map { $_ => "edit" } @root_cats );
    $args{categories} = {} unless (exists($args{categories}));
    %{$args{categories}} = (%categories, %{$args{categories}});

    my @all_desks = Krang::Desk->find(ids_only=>1);
    my %desks = ( map { $_ => "edit" } @all_desks );
    $args{desks} = {} unless (exists($args{desks}));
    %{$args{desks}} = (%desks, %{$args{desks}});


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
    my $sql_from_where_str = "from group_permission ";
    $sql_from_where_str .= "where ". join(" and ", @sql_wheres) ." "  if (@sql_wheres);
    $sql_from_where_str .= "order by ". join(",", @order_by_dirs) ." ";
    $sql_from_where_str .= "limit $offset,$limit"  if ($limit);

    # Build select list and run SQL, return results
    my $dbh = dbh();

    if ($count) {
        # Return count(*)
        my $sql = "select count(*) $sql_from_where_str";
        debug_sql($sql, \@sql_where_data);

        my ($group_count) = $dbh->selectrow_array($sql, undef, @sql_where_data);
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

If an invalid category or desk is specified, save() will croak()
with errors.


=cut

sub save {
    my $self = shift;

    # Validate object or throw up
    $self->validate_group();

    # Insert if this is a new group
    $self->insert_new_group() unless ($self->group_id);

    my $group_id = $self->group_id();

    # Update group object primary fields in database
    my $update_sql = "update group_permission set ";
    $update_sql .= join(", ", map { "$_=?" } FIELDS);
    $update_sql .= " where group_id=?";

    my @update_data = ( map { $self->$_ } FIELDS );
    push(@update_data, $group_id);

    debug_sql($update_sql, \@update_data);

    my $dbh = dbh();
    $dbh->do($update_sql, undef, @update_data);

    # Sanitize categories: Make sure all root categories are specified
    my @root_cats = Krang::Category->find(ids_only=>1, parent_id=>undef);
    my %categories = $self->categories();
    foreach my $cat (@root_cats) {
        $categories{$cat} = "edit" unless (exists($categories{$cat}));
    }

    # Blow away all category perms in database and re-build
    $dbh->do( "delete from category_group_permission where group_id=?",
              undef, $group_id );
    my $cats_sql = "insert into category_group_permission (group_id,category_id,permission_type) values (?,?,?)";
    my $cats_sth = $dbh->prepare($cats_sql);
    while (my ($category_id, $permission_type) = each(%categories)) {
        $cats_sth->execute($group_id, $category_id, $permission_type);
    }

    # Sanitize desks: Make sure all desks are specified
    my @all_desks = Krang::Desk->find(ids_only=>1);
    my %desks = $self->desks();
    foreach my $desk (@all_desks) {
        $desks{$desk} = "edit" unless (exists($desks{$desk}));
    }

    # Blow away all desk perms in database and re-build
    $dbh->do( "delete from desk_group_permission where group_id=?",
              undef, $group_id );
    my $desks_sql = "insert into desk_group_permission (group_id,desk_id,permission_type) values (?,?,?)";
    my $desks_sth = $dbh->prepare($desks_sql);
    while (my ($desk_id, $permission_type) = each(%desks)) {
        $desks_sth->execute($group_id, $desk_id, $permission_type);
    }

    # Rebuild category permissions cache for this group
    $self->rebuild_group_permissions_cache();
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
                                 user_group_permission
                                 group_permission );

    foreach my $table (@delete_from_tables) {
        $dbh->do( "delete from $table where group_id=?",
                  undef, $group_id );
    }
}


=item add_category_permissions()

  Krang::Group->add_category_permissions($category);

This method is expected to be called by Krang::Category when a new 
category is added to the system.  As the nature of categories are 
hierarchal, it is expected that new categories have no descendants.

Given a particular category object, this method will update the 
category_group_permission_cache table to add this category for all 
groups.

In the case of a "root" category (no parent_id, associated with a 
site), permissions will be added to the category_group_permission
table for each group, defaulting to "edit".

=cut

sub add_category_permissions {
    my $self = shift;
    my ($category) = @_;

    croak ("No category provided") unless ($category && ref($category));

    # Get category_id -- needed for update
    my $category_id = $category->category_id();

    # Get category parent -- needed for default perms
    my $parent_id = $category->parent_id();

    # Set up STHs for queries and update
    my $dbh = dbh();
    my $sth_get_parent_perm = $dbh->prepare(qq/
                                            select may_see, may_edit from category_group_permission_cache 
                                            where category_id=? and group_id=?
                                            /);

    # Insert into cache table for each category/group
    my $sth_set_perm = $dbh->prepare(qq/
                                     insert into category_group_permission_cache
                                     (category_id, group_id, may_see, may_edit) values (?,?,?,?)
                                     /);

    # Check for existing permissions
    my $sth_check_group_perm = $dbh->prepare(qq/
                                             select permission_type from category_group_permission
                                             where category_id=? and group_id=?
                                             /);

    # For new "root" categories
    my $sth_add_group_perm = $dbh->prepare(qq/
                                           insert into category_group_permission
                                           (category_id, group_id, permission_type) values (?,?,"edit")
                                           /);

    # Iterate through groups, default to permission of parent category, or "edit"
    my @group_ids = $self->find(ids_only=>1);
    foreach my $group_id (@group_ids) {
        # Default to "edit"
        my $may_see = 1;
        my $may_edit = 1;

        # Get parent category permissions, if any
        if ($parent_id) {
            # Non-root categories inherit permissions of their parent
            $sth_get_parent_perm->execute($parent_id, $group_id);
            ($may_see, $may_edit) = $sth_get_parent_perm->fetchrow_array();
            $sth_get_parent_perm->finish();
        }

        # Apply permissions if they exist (rebuild case)
        $sth_check_group_perm->execute($category_id, $group_id);
        my ($permission_type) = $sth_check_group_perm->fetchrow_array();
        $sth_check_group_perm->finish();

        if ($permission_type) {
            $may_edit = 0 unless ($permission_type eq "edit");
            $may_see  = 0 if ($permission_type eq "hide");
        } else {
            # Root categories get added to category_group_permission
            $sth_add_group_perm->execute($category_id, $group_id) unless ($parent_id);
        }

        # Update category perms cache for this group
        $sth_set_perm->execute($category_id, $group_id, $may_see, $may_edit);
    }

}



=item delete_category_permissions()

  Krang::Group->delete_category_permissions($category);

This method is expected to be called by Krang::Category when a  
category is about to be removed from the system.  As the nature of categories are 
hierarchal, it is expected that deleted categories have no descendants.

Given a particular category object, update the category_group_permission_cache
table to delete this category for all groups.

Also, delete from category_group_permission all references to this 
category.

=cut

sub delete_category_permissions {
    my $self = shift;
    my ($category) = @_;

    croak ("No category provided") unless ($category && ref($category));

    # Get category_id from object
    my $category_id = $category->category_id();

    my $dbh = dbh();

    # Get rid of permissions cache
    $dbh->do( "delete from category_group_permission_cache where category_id=?",
              undef, $category_id );

    # Get rid of permissions
    $dbh->do( "delete from category_group_permission where category_id=?",
              undef, $category_id );
}



=item rebuild_category_cache()

  Krang::Group->rebuild_category_cache();

This class method will clear the table category_group_permission_cache 
and rebuild it from the category_group_permission table.  This logically 
iterates through each group and applying the permissions for each category 
according to the configuration.

Permissions for a particular category are applicable to all descendant
categories.  In lieu of a specific disposition for a particular category
(as is the case if a group does not specify access for a site), permissions
will default to "edit". 


=cut

sub rebuild_category_cache {
    my $self = shift;

    my $dbh = dbh();

    # Clear cache table
    $dbh->do( "delete from category_group_permission_cache", undef);

    # Traverse category hierarchy
    my @root_cats = Krang::Category->find(parent_id=>undef);
    foreach my $category (@root_cats) {
        $self->rebuild_category_cache_process_category($category);
    }
}



=item add_desk_permissions()

  Krang::Group->add_desk_permissions($desk);

This method is expected to be called by Krang::Desk when a new 
desk is added to the system.

Given a particular desk object, this method will update the 
desk_group_permission table to add this desk for all 
groups.

=cut

sub add_desk_permissions {
    my $self = shift;
    my ($desk) = @_;

    croak ("No desk provided") unless ($desk && ref($desk));

    # Get desk_id -- needed for update
    my $desk_id = $desk->desk_id();

    # Set up STHs for queries and update
    my $dbh = dbh();
    my $sth_add_group_perm = $dbh->prepare(qq/
                                           insert into desk_group_permission
                                           (desk_id, group_id, permission_type) values (?,?,"edit")
                                           /);

    # Iterate through groups, default to "edit"
    my @group_ids = $self->find(ids_only=>1);
    foreach my $group_id (@group_ids) {
        # Set permissions for this new desk
        $sth_add_group_perm->execute($desk_id, $group_id);
    }
}



=item delete_desk_permissions()

  Krang::Group->delete_desk_permissions($desk);

This method is expected to be called by Krang::Desk when a  
desk is about to be removed from the system.

Given a particular desk object, update the desk_group_permission
table to delete this desk for all groups.

=cut

sub delete_desk_permissions {
    my $self = shift;
    my ($desk) = @_;

    croak ("No desk provided") unless ($desk && ref($desk));

    # Get desk_id from object
    my $desk_id = $desk->desk_id();

    my $dbh = dbh();

    # Get rid of permissions
    $dbh->do( "delete from desk_group_permission where desk_id=?",
              undef, $desk_id );
}





=item user_desk_permissions()

  my %desk_perms = Krang::Group->user_desk_permissions();

This method is expected to be used by Krang::Story and any other 
modules which need to know if the current user has access to a particular desk.
This method returns a hash table which maps desk_id values to 
security levels, "edit", "read-only", or "hide".

This method combines the permissions of all the groups with which
the user is affiliated.  Group permissions are combined using
a "most privilege" algorithm.  In other words, if a user is 
assigned to the following groups:

   Group A =>  Desk 1 => "edit"
               Desk 2 => "read-only"
               Desk 3 => "read-only"

   Group B =>  Desk 1 => "read-only"
               Desk 2 => "hide"
               Desk 3 => "edit"

In this case, the resultant permissions for this user will be:

   Desk 1 => "edit"
   Desk 2 => "read-only"
   Desk 3 => "edit"


You can also request permissions for a particular desk by specifying it by ID:

  my $desk1_access = Krang::Group->user_desk_permissions($desk_id);

=cut


sub user_desk_permissions {}




=item user_asset_permissions()

  my %asset_perms = Krang::Group->user_asset_permissions();

This method is expected to be used by all modules which need to know 
if the current user has access to a particular asset class.  This method returns 
a hash table which maps asset types ("story", "media", and "template") 
to security levels, "edit", "read-only", or "hide".

This method combines the permissions of all the groups with which
the user is affiliated.  Group permissions are combined using
a "most privilege" algorithm.  In other words, if a user is 
assigned to the following groups:

   Group A =>  story    => "read-only"
               media    => "edit"
               template => "read-only"

   Group B =>  story    => "edit"
               media    => "read-only"
               template => "hide"

In this case, the resultant permissions for this user will be:

   story    => "edit"
   media    => "edit"
   template => "read-only"


You can also request permissions for a particular asset by specifying it:

  my $media_access = Krang::Group->user_desk_permissions('media');

=cut


sub user_asset_permissions {}




=item user_admin_permissions()

  my %admin_perms = Krang::Group->user_admin_permissions($user);

This method is expected to be used by all modules which need to know 
if the current user has access to a particular administrative function.

This method returns a hash table which maps admin functions
to Boolean values (1 or 0) designating whether or not the user is 
allowed to use that particular function.  Following is the list of 
functions:

  may_publish
  may_checkin_all
  admin_users
  admin_users_limited
  admin_groups
  admin_contribs
  admin_sites
  admin_categories
  admin_jobs
  admin_desks

This method combines the permissions of all the groups with which
the user is affiliated.  Group permissions are combined using
a "most privilege" algorithm.  In other words, if a user is 
assigned to the following groups:

   Group A => may_publish         => 1
              may_checkin_all     => 0
              admin_users         => 1
              admin_users_limited => 1
              admin_groups        => 0
              admin_contribs      => 1
              admin_sites         => 0
              admin_categories    => 1
              admin_jobs          => 1
              admin_desks         => 0


   Group B => may_publish         => 0
              may_checkin_all     => 1
              admin_users         => 1
              admin_users_limited => 0
              admin_groups        => 1
              admin_contribs      => 0
              admin_sites         => 0
              admin_categories    => 0
              admin_jobs          => 1
              admin_desks         => 1

In this case, the resultant permissions for this user will be:

   may_publish         => 1
   may_checkin_all     => 1
   admin_users         => 1
   admin_users_limited => 0
   admin_groups        => 1
   admin_contribs      => 1
   admin_sites         => 0
   admin_categories    => 1
   admin_jobs          => 1
   admin_desks         => 1


(N.B.:  The admin function "admin_users_limited" is deemed to be
a high privilege when it is set to 0 -- not 1.)


You can also request permissions for a particular admin function by specifying it:

  my $may_publish = Krang::Group->user_desk_permissions('may_publish');


=cut


sub user_admin_permissions {}





###########################
####  PRIVATE METHODS  ####
###########################

# Re-build category cache for this category, and descend by recursion
sub rebuild_category_cache_process_category {
    my $self = shift;
    my ($category) = @_;

    # Add categories
    $self->add_category_permissions($category);

    # Descend and recurse
    my @children = $category->children();
    foreach my $category (@children) {
        $self->rebuild_category_cache_process_category($category);
    }
}


# Re-build category permissions cache for a particular group.
# Used when a group is saved (added or edited)
sub rebuild_group_permissions_cache {
    my $self = shift;

    # Get category permissions -- we're going to be passing this around
    my %category_perms = $self->categories();

    # Get $dbh -- we're passing this around, too
    my $dbh = dbh();

    # Traverse category hierarchy, selectively applying permissions as needed
    my @root_cats = Krang::Category->find(parent_id=>undef);
    foreach my $category (@root_cats) {
        $self->rebuild_group_permissions_cache_process_category($category, \%category_perms, $dbh);
    }
}


# Traverse category hierarchy, selectively applying permissions as needed
sub rebuild_group_permissions_cache_process_category {
    my $self = shift;
    my ($category, $category_perms, $dbh) = @_;

    my $category_id = $category->category_id();

    # Is this category specified in the permissions table?
    if (my $permission_type = $category_perms->{$category_id}) {
        my $group_id = $self->group_id();

        # Assemble list of category IDs to update -- all descendants
        my @update_categories = ( $category_id, $category->descendants(ids_only=>1) );
        my $update_categories_str = join(",", @update_categories);

        # Set up permissions
        my ($may_edit, $may_see) = (1, 1);
        $may_edit = 0 unless ($permission_type eq "edit");
        $may_see  = 0 if ($permission_type eq "hide");

        my $update_sql = qq(
                            update category_group_permission_cache
                            set may_see=?, may_edit=?
                            where group_id=? AND category_id IN ($update_categories_str)
                           );

        # Do update cache table
        $dbh->do($update_sql, undef, $may_see, $may_edit, $group_id);
    }

    # Descend and recurse
    my @children = $category->children();
    foreach my $category (@children) {
        $self->rebuild_group_permissions_cache_process_category($category, $category_perms, $dbh);
    }
}


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
        # Make sure permission level makes sense
        croak ("Invalid security level '$level' for category_id '$cat'")
          unless (grep { $level eq $_ } @valid_levels);

        # Make sure category exists
        croak ("No such category_id '$cat'") 
          unless (Krang::Category->find(category_id=>$cat, count=>1));
    }

    # Check desks
    my %desks = $self->desks;
    while (my ($desk, $level) = each(%desks)) {
        # Make sure permission level makes sense
        croak ("Invalid security level '$level' for desk_id '$desk'")
          unless (grep { $level eq $_ } @valid_levels);

        # Make sure desk exists
        croak ("No such desk_id '$desk'") 
          unless (Krang::Desk->find(desk_id=>$desk, count=>1));
    }

    # Is the name unique?
    my $group_id = $self->group_id();
    my $name = $self->name();

    my $dbh = dbh();
    my $is_dup_sql = "select group_id from group_permission where name = ? and group_id != ?";
    my ($dup_id) = $dbh->selectrow_array($is_dup_sql, undef, $name, $group_id);

    # If dup, throw exception
    if ($dup_id) {
        Krang::Group::DuplicateName->throw( message => "duplicate group name", group_id => $dup_id );
    }
}


# Create a new database record for group.  Set group_id in object.
sub insert_new_group {
    my $self = shift;

    my $dbh = dbh();
    $dbh->do("insert into group_permission (group_id) values (NULL)") || die($dbh->errstr);

    my $group_id = $dbh->{'mysql_insertid'};
    $self->{group_id} = $group_id;

    # Insert group/category permissions
    my $cat_perm_sql = qq/ insert into category_group_permission
                           (category_id, group_id, permission_type)
                           values (?,?,"edit") /;
    my $cat_perm_sth = $dbh->prepare($cat_perm_sql);
    my @root_cats = Krang::Category->find(ids_only=>1, parent_id=>undef);
    foreach my $category_id (@root_cats) {
        $cat_perm_sth->execute($category_id, $group_id);
    }

    # Insert group/category permissions cache
    my $cat_perm_cache_sql = qq/ insert into category_group_permission_cache
                           (category_id, group_id, may_see, may_edit)
                           values (?,?,1,1) /;
    my $cat_perm_cache_sth = $dbh->prepare($cat_perm_cache_sql);
    my @all_cats = Krang::Category->find(ids_only=>1);
    foreach my $category_id (@all_cats) {
        $cat_perm_cache_sth->execute($category_id, $group_id);
    }
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

