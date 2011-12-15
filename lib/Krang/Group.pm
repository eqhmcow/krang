package Krang::Group;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::Group - Interface to manage Krang permissions


=head1 SYNOPSIS

    # Include the library
    use Krang::ClassLoader 'Group';

    # Create a new group
    my $group = pkg('Group')->new(
        name       => 'Car Editors',
        categories => {
            1  => 'read-only',
            2  => 'edit',
            23 => 'hide'
        },
        desks => {
            1  => 'read-only',
            2  => 'edit',
            23 => 'hide'
        },
        may_publish          => 1,
        may_checkin_all      => 1,
        admin_users          => 1,
        admin_users_limited  => 1,
        admin_groups         => 1,
        admin_contribs       => 1,
        admin_sites          => 1,
        admin_categories     => 1,
        admin_categories_ftp => 1,
        admin_jobs           => 1,
        admin_scheduler      => 1,
        admin_desks          => 1,
        admin_lists          => 1,
        admin_delete         => 1,
        may_view_trash       => 1,
        asset_story          => 'edit',
        asset_media          => 'read-only',
        asset_template       => 'hide'
    );

    # Retrieve an existing group by ID
    my ($group) = pkg('Group')->find(group_id => 123);

    # Retrieve multiple existing groups by ID
    my @groups = pkg('Group')->find(group_ids => [1, 2, 3]);

    # Find groups by exact name
    my @groups = pkg('Group')->find(name => 'Boat Editors');

    # Find groups by name pattern
    my @groups = pkg('Group')->find(name_like => '%editor%');

    # Save group
    $group->save();

    # Delete group
    $group->delete();

    # Get group ID
    my $group_id = $self->group_id();

    # Accessors/Mutators
    my $name                 = $group->name();
    my $may_publish          = $group->may_publish();
    my $may_checkin_all      = $group->may_checkin_all();
    my $admin_users          = $group->admin_users();
    my $admin_users_limited  = $group->admin_users_limited();
    my $admin_groups         = $group->admin_groups();
    my $admin_contribs       = $group->admin_contribs();
    my $admin_sites          = $group->admin_sites();
    my $admin_categories     = $group->admin_categories();
    my $admin_categories_ftp = $group->admin_categories_ftp();
    my $admin_jobs           = $group->admin_jobs();
    my $admin_scheduler      = $group->admin_scheduler();
    my $admin_desks          = $group->admin_desks();
    my $admin_desks          = $group->admin_lists();
    my $admin_delete         = $group->admin_delete();
    my $may_view_trash       = $group->may_view_trash();
    my $asset_story          = $group->asset_story();
    my $asset_media          = $group->asset_media();
    my $asset_template       = $group->asset_template();
    my %categories           = $group->categories();
    my %desks                = $group->desks();

    # Category permissions cache management
    pkg('Group')->add_category_permissions($category);
    pkg('Group')->delete_category_permissions($category);
    pkg('Group')->rebuild_category_cache();

    # Krang::Desk permission management
    pkg('Group')->add_desk_permissions($desk);
    pkg('Group')->delete_desk_permissions($desk);

    # Evaluate permissions for the currently logged-in user
    my %desk_perms  = pkg('Group')->user_desk_permissions();
    my %asset_perms = pkg('Group')->user_asset_permissions();
    my %admin_perms = pkg('Group')->user_admin_permissions();

=head1 DESCRIPTION

Krang::Group provides access to manipulate Krang's permission groups.
These groups control authorization within Krang as documented in the
file F<krang/docs/permissions.pod>.

=head1 INTERFACE

The following methods are provided by Krang::Group.

=over 4

=cut

# Required modules
use Carp;
use Krang::ClassLoader DB  => qw(dbh);
use Krang::ClassLoader Log => qw(debug);
use Krang::ClassLoader 'Desk';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'UUID';
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'Cache';

# Exceptions
use Exception::Class (
    'Krang::Group::DuplicateName' => {fields => ['group_id']},
    'Krang::Group::Dependent'     => {fields => 'dependents'}
);

# Database fields in table group_permission, asidde from group_id
use constant FIELDS => qw( name
  group_uuid
  may_publish
  may_checkin_all
  admin_users
  admin_users_limited
  admin_groups
  admin_contribs
  admin_sites
  admin_categories
  admin_categories_ftp
  admin_jobs
  admin_scheduler
  admin_desks
  admin_lists
  admin_delete
  may_view_trash
  asset_story
  asset_media
  asset_template );

# Constructor/Accessor/Mutator setup
use Krang::ClassLoader MethodMaker => (
    new_with_init => 'new',
    new_hash_init => 'hash_init',
    get           => ["group_id"],
    get_set       => [FIELDS],
    hash          => [
        qw( categories
          desks )
    ]
);

sub id_meth   { 'group_id' }
sub uuid_meth { 'group_uuid' }

=item new()

    my $group = pkg('Group')->new();

This method returns a new Krang::Group object.  You may pass a hash
into C<new()> containing initial values for the object properties.
These properties are:

=over

=item * name

Name of this group

=item * asset_story

Story asset security level

=item * asset_media

Media asset security level

=item * asset_template

Template asset security level

=item * categories (hash)

Map category ID to security level

=item * desks (hash)

Map desk ID to security level

=back

Security levels may be "edit", "read-only", or "hide".

In addition to these properties, the following properties may be specified
using Boolean (1 or 0) values:

=over

=item may_publish

=item may_checkin_all

=item admin_users

=item admin_users_limited

=item admin_groups

=item admin_contribs

=item admin_sites

=item admin_categories

=item admin_categories_ftp

=item admin_jobs

=item admin_scheduler

=item admin_desks

=item admin_lists

=back

=cut

sub init {
    my $self = shift;
    my %args = (@_);

    # Set up default values
    my %defaults = (
        name                 => "",
        may_publish          => 0,
        may_checkin_all      => 0,
        admin_users          => 0,
        admin_users_limited  => 0,
        admin_groups         => 0,
        admin_contribs       => 0,
        admin_sites          => 0,
        admin_categories     => 0,
        admin_categories_ftp => 0,
        admin_jobs           => 0,
        admin_scheduler      => 0,
        admin_desks          => 0,
        admin_lists          => 0,
        asset_story          => 'edit',
        asset_media          => 'edit',
        asset_template       => 'edit',
        group_uuid           => pkg('UUID')->new(),
    );

    # Set up defaults for category and desk permissions
    my @root_cats = pkg('Category')->find(ids_only => 1, parent_id => undef);
    my %categories = (map { $_ => "edit" } @root_cats);
    $args{categories} = {} unless (exists($args{categories}));
    %{$args{categories}} = (%categories, %{$args{categories}});

    my @all_desks = pkg('Desk')->find(ids_only => 1);
    my %desks = (map { $_ => "edit" } @all_desks);
    $args{desks} = {} unless (exists($args{desks}));
    %{$args{desks}} = (%desks, %{$args{desks}});

    # finish the object
    $self->hash_init(%defaults, %args);

    # Set default group_id
    $self->{group_id} = 0;

    return $self;
}

=item find()

    my @groups = pkg('Group')->find();

Retrieve Krang::Group objects from database based on a search
specification.  Searches are specified by passing a hash to C<find()>
with search fields as keys and search terms as the values of those keys.
For example, the following would retrieve all groups with the word
"admin" in the group name:

    my @groups = pkg('Group')->find(name_like => '%admin%');

Search terms may be combined to further narrow the result set.
For example, the following will limit the above search to groups whose
IDs are in an explicit list:

    my @groups = pkg('Group')->find(
        name_like => '%admin%',
        group_ids => [1, 5, 10, 34]
    );

The following search fields are recognized by C<Krang::Group->find()>:

=over

=item * simple_search

A scalar string, matches to name

=item * group_id

Retrieve a specific group by ID

=item * group_ids

Array reference of group_ids which should be retrieved

=item * name

Exactly match the group name

=item * name_like

SQL LIKE-match the group name

=back

The C<find()> method provides meta terms to control how the data should
be returned:

=over

=item * count

Causes C<find()> to return the number of matches instead of the actual
objects.

=item * ids_only

Causes C<find()> to return the IDs of the matching groups instead of
the instantiated group objects.

=item * order_by

The group field by which the found objects should be sorted.  Defaults to
"name".

=item * order_desc

Results will be sorted in descending order if this is set to "1",
ascending if "0".  Defaults to "0".

=item * limit

The number of objects to be returned.  Defaults to all.

=item * offset

The index into the result set at which objects should be returned.
Defaults to "0" -- the first record.

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;

    # check the cache if we're looking for a single group
    my $cache_worthy = (
        pkg('Cache')->active and keys(%args) == 1 and (exists $args{group_id}
            or exists $args{group_ids})
    ) ? 1 : 0;
    if ($cache_worthy) {
        my @ids = (
            exists $args{group_ids}
            ? @{$args{group_ids}}
            : ($args{group_id})
        );
        my @groups = map { pkg('Cache')->get('Krang::Group' => $_) } @ids;
        return @groups unless not @groups or grep { not defined } @groups;
    }

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
      group_uuid
      name
      name_like
    );

    foreach my $arg (keys(%args)) {
        croak("Invalid find arg '$arg'")
          unless (grep { $arg eq $_ } @valid_find_params);
    }

    # For SQL query
    my $order_by = delete $args{order_by} || 'name';
    my $order_dir = delete $args{order_desc} ? 'DESC' : 'ASC';
    my $limit    = delete $args{limit}    || 0;
    my $offset   = delete $args{offset}   || 0;
    my $count    = delete $args{count}    || 0;
    my $ids_only = delete $args{ids_only} || 0;

    # check for invalid argument sets
    croak(  __PACKAGE__
          . "->find(): 'count' and 'ids_only' were supplied. "
          . "Only one can be present.")
      if $count and $ids_only;

    my @sql_wheres     = ();
    my @sql_where_data = ();

    #
    # Build search query
    #

    # simple_search: like searches on name
    if (my $search = $args{simple_search}) {
        my @words = split(/\W+/, $search);
        my @like_words = map { "\%$_\%" } @words;
        push(@sql_wheres, (map { "name LIKE ?" } @like_words));
        push(@sql_where_data, @like_words);
    }

    # group_id
    if (my $search = $args{group_id}) {
        push(@sql_wheres,     "group_id = ?");
        push(@sql_where_data, $search);
    }

    # group_uuid
    if (my $search = $args{group_uuid}) {
        if (defined $search) {
            push(@sql_wheres,     "group_uuid = ?");
            push(@sql_where_data, $search);
        } else {
            push(@sql_wheres, "group_id IS NULL");
        }
    }

    # group_ids
    if (my $search = $args{group_ids}) {
        croak("group_ids must be an array ref")
          unless ($search and (ref($search) eq 'ARRAY'));
        croak("group_ids array ref may only contain numeric IDs")
          if (grep { $_ =~ /\D/ } @$search);
        my $group_ids_str = join(",", @$search);
        push(@sql_wheres, "group_id IN ($group_ids_str)");
    }

    # name
    if (my $search = $args{name}) {
        push(@sql_wheres,     "name = ?");
        push(@sql_where_data, $search);
    }

    # name_like
    if (my $search = $args{name_like}) {
        $search =~ s/\W+/%/g;
        push(@sql_wheres,     "name LIKE ?");
        push(@sql_where_data, "$search");
    }

    #
    # Build SQL query
    #

    # Handle order by/dir
    my @order_bys = split(/,/, $order_by);
    my @order_by_dirs = map { "$_ $order_dir" } @order_bys;

    # Build SQL where, order by and limit clauses as string -- same for all situations
    my $sql_from_where_str = "FROM group_permission ";
    $sql_from_where_str .= "WHERE " . join(" AND ", @sql_wheres) . " " if (@sql_wheres);
    $sql_from_where_str .= "ORDER BY " . join(",", @order_by_dirs) . " ";
    $sql_from_where_str .= "LIMIT $offset,$limit" if ($limit);

    # Build select list and run SQL, return results
    my $dbh = dbh();

    if ($count) {

        # Return count(*)
        my $sql = "SELECT COUNT(*) $sql_from_where_str";
        debug_sql($sql, \@sql_where_data);

        my ($group_count) = $dbh->selectrow_array($sql, undef, @sql_where_data);
        return $group_count;

    } elsif ($ids_only) {

        # Return group_ids
        my $sql = "SELECT group_id $sql_from_where_str";
        debug_sql($sql, \@sql_where_data);

        my $sth = $dbh->prepare($sql);
        $sth->execute(@sql_where_data);
        my @group_ids = ();
        while (my ($group_id) = $sth->fetchrow_array()) {
            push(@group_ids, $group_id);
        }
        $sth->finish();
        return @group_ids;

    } else {

        # Return objects
        my $sql_fields = join(",", ("group_id", FIELDS));
        my $sql = "SELECT $sql_fields $sql_from_where_str";
        debug_sql($sql, \@sql_where_data);

        my $sth = $dbh->prepare($sql);
        $sth->execute(@sql_where_data);
        my @groups = ();
        while (my $group_data = $sth->fetchrow_hashref) {
            push(@groups, $self->new_from_db($group_data));
        }
        $sth->finish();

        # set in the cache if this was a simple find
        if ($cache_worthy) {
            pkg('Cache')->set('Krang::Group' => $_->{group_id} => $_) for @groups;
        }

        return @groups;
    }
}

=item save();

    $group->save();

Save the group object to the database.  If this is a new group object
it will be inserted into the database and group_id will be defined.

If another existing group has the same name as the group you're trying
to save, a C<Krang::Group::DuplicateName> exception will be thrown.

In all cases, the group object's configured category and desk permissions
will be checked for validity and sanitized if necessary.

For categories, this means that if a root category is not specified in the
C<categories()> hash, it will be silently created with "edit" permissions.

In the case of desks, missing desks will be created with "edit"
permissions.

If an invalid category or desk is specified, C<save()> will C<croak()>
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
    my $update_sql = "UPDATE group_permission SET ";
    $update_sql .= join(", ", map { "$_ = ?" } FIELDS);
    $update_sql .= " WHERE group_id = ?";

    my @update_data = (map { $self->$_ } FIELDS);
    push(@update_data, $group_id);

    debug_sql($update_sql, \@update_data);

    my $dbh = dbh();
    $dbh->do($update_sql, undef, @update_data);

    # Sanitize categories: Make sure all root categories are specified
    my @root_cats = pkg('Category')->find(ids_only => 1, parent_id => undef);
    my %categories = $self->categories();
    foreach my $cat (@root_cats) {
        $categories{$cat} = "edit" unless (exists($categories{$cat}));
    }

    # Blow away all category perms in database and re-build
    $dbh->do("DELETE FROM category_group_permission WHERE group_id = ?", undef, $group_id);
    my $cats_sql =
      "INSERT INTO category_group_permission (group_id, category_id, permission_type) VALUES (?,?,?)";
    my $cats_sth = $dbh->prepare($cats_sql);
    while (my ($category_id, $permission_type) = each(%categories)) {
        $cats_sth->execute($group_id, $category_id, $permission_type);
    }

    # Sanitize desks: Make sure all desks are specified
    my @all_desks = pkg('Desk')->find(ids_only => 1);
    my %desks = $self->desks();
    foreach my $desk (@all_desks) {
        $desks{$desk} = "edit" unless (exists($desks{$desk}));
    }

    # Blow away all desk perms in database and re-build
    $dbh->do("DELETE FROM desk_group_permission WHERE group_id = ?", undef, $group_id);
    my $desks_sql =
      "INSERT INTO desk_group_permission (group_id, desk_id, permission_type) VALUES (?,?,?)";
    my $desks_sth = $dbh->prepare($desks_sql);
    while (my ($desk_id, $permission_type) = each(%desks)) {
        $desks_sth->execute($group_id, $desk_id, $permission_type);
    }

    $self->update_group_user_permissions();
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

    # throws dependent exception if one exists
    $self->dependent_check();

    # Blow away data
    my $dbh                = dbh();
    my @delete_from_tables = qw( category_group_permission
      desk_group_permission
      user_group_permission
      group_permission );

    foreach my $table (@delete_from_tables) {
        $dbh->do("DELETE FROM $table WHERE group_id = ?", undef, $group_id);
    }
}

=item dependent_check()
    
Check to see if any users are associated with this group.  If there are,
this group should not be deleted- and an exception is thrown.

=cut

sub dependent_check {
    my $self       = shift;
    my $id         = shift || $self->{group_id};
    my $dependents = 0;
    my (@info, $login);

    my $query = qq/
        SELECT user.login from user, user_group_permission 
        WHERE user.user_id = user_group_permission.user_id 
        AND user_group_permission.group_id = ?
    /;
    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute($id);
    $sth->bind_col(1, \$login);
    while ($sth->fetch()) {
        push @info, $login;
        $dependents++;
    }

    Krang::Group::Dependent->throw(
        message    => "Group cannot be deleted " . "while users still belong to group.",
        dependents => \@info
    ) if $dependents;

    return $dependents;
}

=item $group->serialize_xml(writer => $writer, set => $set)

Serialize as XML. See L<Krang::DataSet> for details.

=cut

sub serialize_xml {
    my ($self,   %args) = @_;
    my ($writer, $set)  = @args{qw(writer set)};
    local $_;

    # open up <template> linked to schema/template.xsd
    $writer->startTag(
        'group',
        "xmlns:xsi"                     => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation" => 'group.xsd'
    );

    $writer->dataElement(group_id   => $self->{group_id});
    $writer->dataElement(group_uuid => $self->{group_uuid})
      if $self->{group_uuid};
    $writer->dataElement(name => $self->{name});

    # categories
    my %cats = $self->categories;
    foreach my $cat_id (keys %cats) {
        $writer->startTag('category');
        $writer->dataElement(category_id    => $cat_id);
        $writer->dataElement(security_level => $cats{$cat_id});
        $writer->endTag('category');
        $set->add(object => (pkg('Category')->find(category_id => $cat_id))[0], from => $self);
    }

    # desks
    my %desks = $self->desks;
    foreach my $desk_id (keys %desks) {
        $writer->startTag('desk');
        $writer->dataElement(desk_id        => $desk_id);
        $writer->dataElement(security_level => $desks{$desk_id});
        $writer->endTag('desk');
        $set->add(object => (pkg('Desk')->find(desk_id => $desk_id))[0], from => $self);
    }

    $writer->dataElement(may_publish          => $self->{may_publish});
    $writer->dataElement(may_checkin_all      => $self->{may_checkin_all});
    $writer->dataElement(admin_users          => $self->{admin_users});
    $writer->dataElement(admin_users_limited  => $self->{admin_users_limited});
    $writer->dataElement(admin_groups         => $self->{admin_groups});
    $writer->dataElement(admin_contribs       => $self->{admin_contribs});
    $writer->dataElement(admin_sites          => $self->{admin_sites});
    $writer->dataElement(admin_categories     => $self->{admin_categories});
    $writer->dataElement(admin_categories_ftp => $self->{admin_categories_ftp});
    $writer->dataElement(admin_jobs           => $self->{admin_jobs});
    $writer->dataElement(admin_scheduler      => $self->{admin_scheduler});
    $writer->dataElement(admin_desks          => $self->{admin_desks});
    $writer->dataElement(admin_lists          => $self->{admin_lists});
    $writer->dataElement(admin_delete         => $self->{admin_delete});
    $writer->dataElement(may_view_trash       => $self->{may_view_trash});
    $writer->dataElement(asset_story          => $self->{asset_story});
    $writer->dataElement(asset_media          => $self->{asset_media});
    $writer->dataElement(asset_template       => $self->{asset_template});

    # all done
    $writer->endTag('group');

}

=item C<< $group = Krang::Group->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML. See L<Krang::DataSet> for details.

If an incoming group has the same name as an existing group then an
update will occur, unless C<no_update> is set.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set, $no_update) = @args{qw(xml set no_update)};

    # divide FIELDS into simple and complex groups
    my (%complex, %simple);

    # strip out all fields we don't want updated or used or we want to deal with manually.
    @complex{qw(group_id group_uuid)} = ();
    %simple = map { ($_, 1) } grep { not exists $complex{$_} } (FIELDS);

    # parse it up
    my $data = pkg('XML')->simple(
        xml           => $xml,
        forcearray    => ['category', 'desk'],
        suppressempty => 1
    );

    # is there an existing object?
    my $group;

    # start with UUID lookup
    if (not $args{no_uuid} and $data->{group_uuid}) {
        ($group) = $pkg->find(group_uuid => $data->{group_uuid});

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A group object with the UUID '$data->{group_uuid}' already"
              . " exists and no_update is set.")
          if $group and $no_update;
    }

    # proceed to name lookup if no dice
    unless ($group or $args{uuid_only}) {
        ($group) = pkg('Group')->find(name => $data->{name});

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A group object with the name '$data->{name}' already "
              . "exists and no_update is set.")
          if $group and $no_update;
    }

    # is there an existing object?
    if ($group) {
        debug(__PACKAGE__ . "->deserialize_xml : found group");

        # update simple fields
        $group->{$_} = $data->{$_} for keys %simple;

    } else {
        $group = pkg('Group')->new((map { ($_, $data->{$_}) } keys %simple));
    }

    # preserve UUID if available
    $group->{group_uuid} = $data->{group_uuid}
      if $data->{group_uuid} and not $args{no_uuid};

    # take care of category association
    if ($data->{category}) {
        my @categories = @{$data->{category}};
        my %altered_cats;
        foreach my $cat (@categories) {
            $altered_cats{$set->map_id(class => pkg('Category'), id => $cat->{category_id})} =
              $cat->{security_level};
        }

        $group->categories(%altered_cats);
    }

    # take care of desk association
    if ($data->{desk}) {
        my @desks = @{$data->{desk}};
        my %altered_desks;
        foreach my $desk (@desks) {
            $altered_desks{$set->map_id(class => pkg('Desk'), id => $desk->{desk_id})} =
              $desk->{security_level};
        }

        $group->desks(%altered_desks);
    }

    $group->save();

    return $group;
}

=item add_category_permissions()

    pkg('Group')->add_category_permissions($category);

This method is expected to be called by L<Krang::Category> when a
new category is added to the system.  As the nature of categories are
hierarchal, it is expected that new categories have no descendants.

Given a particular category object, this method will update the
C<user_category_permission_cache> table to add this category for all
users.

In the case of a "root" category (no parent_id, associated with a site),
permissions will be added to the C<category_group_permission> table for
each group, defaulting to "edit".

=cut

sub add_category_permissions {
    my $self = shift;
    my ($category) = @_;

    croak("No category provided") unless ($category && ref($category));

    # Get category_id -- needed for update
    my $category_id = $category->category_id();

    # Get category parent -- needed for default perms
    my $parent_id = $category->parent_id();

    # Set up STHs for queries and update
    my $dbh                 = dbh();
    my $sth_get_parent_perm = $dbh->prepare(
        qq/
        SELECT may_see, may_edit FROM user_category_permission_cache 
        WHERE category_id = ? AND user_id = ?
        /
    );

    # Insert into cache table for each category/group
    my $sth_set_perm = $dbh->prepare(
        qq/
        INSERT INTO user_category_permission_cache
        (category_id, user_id, may_see, may_edit) VALUES (?,?,?,?)
        /
    );

    # Check for existing permissions
    my $sth_check_group_perm = $dbh->prepare(
        qq/
        SELECT permission_type FROM category_group_permission
        WHERE category_id = ? AND group_id = ?
        /
    );

    # For new "root" categories
    my $sth_add_group_perm = $dbh->prepare(
        qq/
        INSERT INTO category_group_permission
        (category_id, group_id, permission_type) VALUES (?,?,"edit")
        /
    );

    # root categories start with "edit" if not yet setup
    unless ($parent_id) {
        foreach my $group_id (pkg('Group')->find(ids_only => 1)) {
            $sth_check_group_perm->execute($category_id, $group_id);
            my ($perm) = $sth_check_group_perm->fetchrow_array();
            $sth_add_group_perm->execute($category_id, $group_id) unless $perm;
        }
    }

    my @users = pkg('User')->find();

    foreach my $user (@users) {
        my $may_see  = 0;
        my $may_edit = 0;
        my $see_set  = 0;
        my $edit_set = 0;

        my $user_id = $user->user_id;

        # Get parent category permissions, if any
        if ($parent_id) {

            # Non-root categories inherit permissions of their parent
            $sth_get_parent_perm->execute($parent_id, $user_id);
            my ($p_may_see, $p_may_edit) = $sth_get_parent_perm->fetchrow_array();
            $sth_get_parent_perm->finish();
            if (defined $p_may_see) {
                $may_see = $p_may_see;
                $see_set = 1;
            }
            if (defined $p_may_edit) {
                $may_edit = $p_may_edit;
                $edit_set = 1;
            }
        }

        # Iterate through groups, default to permission of parent category, or "edit"
        my @user_group_ids = $user->group_ids;
        foreach my $group_id (@user_group_ids) {

            # Apply permissions if they exist (rebuild case)
            $sth_check_group_perm->execute($category_id, $group_id);
            my ($permission_type) = $sth_check_group_perm->fetchrow_array();
            $sth_check_group_perm->finish();

            if ($permission_type) {
                ($permission_type eq "edit")
                  ? ($may_edit = 1, $edit_set = 1)
                  : ($may_edit = 0, $edit_set = 1);
                ($permission_type ne "hide")
                  ? ($may_see = 1, $see_set = 1)
                  : ($may_see = 0, $see_set = 1);
            }
        }

        $may_edit = 1 if not $edit_set;
        $may_see  = 1 if not $see_set;

        # Update category perms cache for this user
        $sth_set_perm->execute($category_id, $user_id, $may_see, $may_edit);

    }

}

=item add_user_permissions()

    pkg('Group')->add_user_permissions($user)

This method is expected to be called upon L<Krang::User> save.  It will
add an entry to C<user_category_permission_cache> for each category in
the system, based on the user's permissions there.

=cut 

sub add_user_permissions {
    my $self = shift;
    my ($user) = @_;

    croak("No user provided") unless ($user && ref($user));
    my $user_id = $user->user_id;

    my $dbh = dbh();

    # Get rid of permissions cache entries for this user
    $dbh->do("DELETE FROM user_category_permission_cache WHERE user_id = ?", undef, $user_id);

    # Insert into cache table for each category/group
    my $sth_set_perm = $dbh->prepare(
        qq/
        INSERT INTO user_category_permission_cache
        (category_id, user_id, may_see, may_edit) VALUES (?,?,?,?)
        /
    );

    # Check for existing permissions
    my $sth_check_group_perm = $dbh->prepare(
        qq/
        SELECT permission_type FROM category_group_permission
        WHERE category_id = ? AND group_id = ?
        /
    );

    # do a lookup on a parent
    my $sth_get_parent_perm = $dbh->prepare(
        qq/
        SELECT may_see, may_edit FROM user_category_permission_cache 
        WHERE category_id = ? AND user_id = ?
        /
    );

    # get categories, sorted with parents before children
    my @category = pkg('Category')->find(
        ignore_user => 1,
        order_by    => 'url'
    );

    foreach my $category (@category) {
        my $may_see  = 0;
        my $may_edit = 0;
        my $found    = 0;

        # Get category parent -- needed for default perms
        my $parent_id = $category->parent_id();
        my @group_ids = $user->group_ids();

        foreach my $group_id (@group_ids) {

            # Apply permissions if they exist (rebuild case)
            $sth_check_group_perm->execute($category->category_id, $group_id);
            my ($permission_type) = $sth_check_group_perm->fetchrow_array();
            next unless $permission_type;
            $found = 1;

            if ($permission_type eq "edit") {
                $may_edit = 1;
            } else {
                $may_edit = 0 unless $may_edit;
            }
            if ($permission_type eq "hide") {
                $may_see = 0 unless $may_see;
            } else {
                $may_see = 1;
            }
        }

        unless ($found) {

            # lookup parent permissions and use them
            $sth_get_parent_perm->execute($category->parent_id, $user_id);
            ($may_see, $may_edit) = $sth_get_parent_perm->fetchrow_array();
        }

        # commit permissions
        $sth_set_perm->execute($category->category_id, $user_id, $may_see, $may_edit);
    }
}

=item delete_category_permissions()

    pkg('Group')->delete_category_permissions($category);

This method is expected to be called by L<Krang::Category> when a category
is about to be removed from the system. As the nature of categories are
hierarchal, it is expected that deleted categories have no descendants.

Given a particular category object, update the
C<user_category_permission_cache> table to delete this category for
all groups.

Also, delete from C<category_group_permission> all references to this
category.

=cut

sub delete_category_permissions {
    my $self = shift;
    my ($category) = @_;

    croak("No category provided") unless ($category && ref($category));

    # Get category_id from object
    my $category_id = $category->category_id();

    my $dbh = dbh();

    # Get rid of permissions cache
    $dbh->do("DELETE FROM user_category_permission_cache WHERE category_id = ?", undef, $category_id);

    # Get rid of permissions
    $dbh->do("DELETE FROM category_group_permission WHERE category_id = ?", undef, $category_id);
}

=item rebuild_category_cache()

    pkg('Group')->rebuild_category_cache();

This class method will clear the table user_category_permission_cache and
rebuild it from the C<category_group_permission> table.  This logically
iterates through each group and applying the permissions for each category
according to the configuration.

Permissions for a particular category are applicable to all descendant
categories.  In lieu of a specific disposition for a particular category
(as is the case if a group does not specify access for a site),
permissions will default to "edit".

=cut

sub rebuild_category_cache {
    my $self = shift;
    my $dbh  = dbh();

    # Clear cache table
    $dbh->do("DELETE FROM user_category_permission_cache", undef);

    # Traverse category hierarchy
    my @root_cats = pkg('Category')->find(parent_id => undef, ignore_user => 1);

    foreach my $category (@root_cats) {
        $self->rebuild_category_cache_process_category($category);
    }
}

=item add_desk_permissions()

    pkg('Group')->add_desk_permissions($desk);

This method is expected to be called by L<Krang::Desk> when a new desk
is added to the system.

Given a particular desk object, this method will update the
C<desk_group_permission> table to add this desk for all groups.

=cut

sub add_desk_permissions {
    my $self = shift;
    my ($desk) = @_;

    croak("No desk provided") unless ($desk && ref($desk));

    # Get desk_id -- needed for update
    my $desk_id = $desk->desk_id();

    # Set up STHs for queries and update
    my $dbh                = dbh();
    my $sth_add_group_perm = $dbh->prepare(
        qq/
        INSERT INTO desk_group_permission
        (desk_id, group_id, permission_type) VALUES (?,?,"edit")
        /
    );

    # Iterate through groups, default to "edit"
    my @group_ids = $self->find(ids_only => 1);
    foreach my $group_id (@group_ids) {

        # Set permissions for this new desk
        $sth_add_group_perm->execute($desk_id, $group_id);
    }
}

=item delete_desk_permissions()

    pkg('Group')->delete_desk_permissions($desk);

This method is expected to be called by L<Krang::Desk> when a desk is
about to be removed from the system.

Given a particular desk object, update the C<desk_group_permission>
table to delete this desk for all groups.

=cut

sub delete_desk_permissions {
    my $self = shift;
    my ($desk) = @_;

    croak("No desk provided") unless ($desk && ref($desk));

    # Get desk_id from object
    my $desk_id = $desk->desk_id();

    my $dbh = dbh();

    # Get rid of permissions
    $dbh->do("DELETE FROM desk_group_permission WHERE desk_id = ?", undef, $desk_id);
}

=item user_desk_permissions()

    my %desk_perms = pkg('Group')->user_desk_permissions();

This method is expected to be used by L<Krang::Story> and any other
modules which need to know if the current user has access to a particular
desk.  This method returns a hash table which maps desk_id values to
security levels, "edit", "read-only", or "hide".

This method combines the permissions of all the groups with which the user
is affiliated.  Group permissions are combined using a "most privilege"
algorithm.  In other words, if a user is assigned to the following groups:

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

You can also request permissions for a particular desk by specifying it
by ID:

    my $desk1_access = pkg('Group')->user_desk_permissions($desk_id);

=cut

sub user_desk_permissions {
    my $self    = shift;
    my $desk_id = shift;

    # Just need user_id.  Don't need user.
    # Assumes that user_id is valid and authenticated
    my $user_id = $ENV{REMOTE_USER}
      || croak("No user_id in session");

    my $get_all_group_desks_sql = qq/ 
      SELECT desk_id, permission_type FROM desk_group_permission 
      LEFT JOIN user_group_permission ON desk_group_permission.group_id = user_group_permission.group_id 
      WHERE user_group_permission.user_id = ?
    /;
    my $dbh = dbh();
    my $sth = $dbh->prepare($get_all_group_desks_sql);

    # Used to evaluate permission levels
    my %levels = (
        "hide"      => 1,
        "read-only" => 2,
        "edit"      => 3
    );

    my %desk_access = ();

    $sth->execute($user_id);
    while (my ($desk_id, $permission_type) = $sth->fetchrow_array()) {
        my $curr_access_level = $levels{$desk_access{$desk_id} || ""} || 0;
        my $new_access_level = $levels{$permission_type};
        $desk_access{$desk_id} = $permission_type
          if ($new_access_level > $curr_access_level);
    }

    # Now that we have the table of desk access levels, return results
    return $desk_access{$desk_id} if ($desk_id);

    # Return whole table if no desk specified
    return %desk_access;
}

=item user_asset_permissions()

    my %asset_perms = pkg('Group')->user_asset_permissions();

This method is expected to be used by all modules which need to know if
the current user has access to a particular asset class.  This method
returns a hash table which maps asset types ("story", "media", and
"template") to security levels, "edit", "read-only", or "hide".

This method combines the permissions of all the groups with which the user
is affiliated.  Group permissions are combined using a "most privilege"
algorithm.  In other words, if a user is assigned to the following groups:

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

    my $media_access = pkg('Group')->user_asset_permissions('media');

=cut

sub user_asset_permissions {
    my $self  = shift;
    my $asset = shift;

    # Assumes that user_id is valid and authenticated
    my $user_id = $ENV{REMOTE_USER}
      || croak("No user_id in session");
    my ($user) = pkg('User')->find(user_id => $user_id);
    croak("Can't find user id '$user_id'") unless ($user && ref($user));

    # Get groups for this user
    my @user_group_ids = $user->group_ids();
    my @groups = (pkg('Group')->find(group_ids => \@user_group_ids));

    # Used to evaluate permission levels
    my %levels = (
        "hide"      => 1,
        "read-only" => 2,
        "edit"      => 3
    );

    my @assets       = qw(story media template);
    my %asset_access = ();

    # Iterate through each asset
    foreach my $asset (@assets) {
        my $asset_method = "asset_" . $asset;

        # Iterate through groups
        foreach my $group (@groups) {
            my $curr_access_level = $levels{$asset_access{$asset} || ""} || 0;
            my $permission_type   = $group->$asset_method();
            my $new_access_level  = $levels{$permission_type};

            if ($new_access_level > $curr_access_level) {
                $asset_access{$asset} = $permission_type;
            }
        }
    }

    # Now that we have the table of asset access levels, return results
    return $asset_access{$asset} if ($asset);

    # Return whole table if no desk specified
    return %asset_access;
}

=item user_admin_permissions()

    my %admin_perms = pkg('Group')->user_admin_permissions();
    my $perms       = pkg('Group')->user_admin_permissions($permission);

This method is expected to be used by all modules which need to know if
the current user has access to a particular administrative function.

This method returns a hash table which maps admin functions to Boolean
values (1 or 0) designating whether or not the user is allowed to use
that particular function.  Following is the list of functions:

=over

=item may_publish

=item may_checkin_all

=item admin_users

=item admin_users_limited

=item admin_groups

=item admin_contribs

=item admin_sites

=item admin_categories

=item admin_categories_ftp

=item admin_jobs

=item admin_scheduler

=item admin_desks

=item admin_lists

=item admin_delete

=item may_view_trash

=back

This method combines the permissions of all the groups with which the user
is affiliated.  Group permissions are combined using a "most privilege"
algorithm.  In other words, if a user is assigned to the following groups:

    Group A => may_publish         => 1
               may_checkin_all     => 0
               admin_users         => 1
               admin_users_limited => 1
               admin_groups        => 0
               admin_contribs      => 1
               admin_sites         => 0
               admin_categories    => 1
               admin_categories_ftp    => 1
               admin_jobs          => 1
               admin_scheduler     => 1
               admin_desks         => 0
               admin_lists         => 0
               admin_delete        => 0
               may_view_trash      => 0

    Group B => may_publish         => 0
               may_checkin_all     => 1
               admin_users         => 1
               admin_users_limited => 0
               admin_groups        => 1
               admin_contribs      => 0
               admin_sites         => 0
               admin_categories    => 0
               admin_categories_ftp    => 0
               admin_jobs          => 1
               admin_scheduler     => 1
               admin_desks         => 1
               admin_lists         => 0
               admin_delete        => 1
               may_view_trash      => 1

In this case, the resultant permissions for this user will be:

    may_publish             => 1
    may_checkin_all         => 1
    admin_users             => 1
    admin_users_limited     => 0
    admin_groups            => 1
    admin_contribs          => 1
    admin_sites             => 0
    admin_categories        => 1
    admin_categories_ftp    => 1
    admin_jobs              => 1
    admin_scheduler         => 1
    admin_desks             => 1
    admin_lists             => 0
    admin_delete            => 1
    may_view_trash          => 1

(N.B.:  The admin function "admin_users_limited" is deemed to be a high
privilege when it is set to 0 -- not 1.)

You can also request permissions for a particular admin function by
specifying it:

    my $may_publish = pkg('Group')->user_admin_permissions('may_publish');

=cut

sub user_admin_permissions {
    my $self       = shift;
    my $admin_perm = shift;

    # Assumes that user_id is valid and authenticated
    my $user_id = $ENV{REMOTE_USER}
      || croak("No user_id in session");
    my ($user) = pkg('User')->find(user_id => $user_id);
    croak("Can't find user id '$user_id'") unless ($user && ref($user));

    # Get groups for this user
    my @user_group_ids = $user->group_ids();
    my @groups = (pkg('Group')->find(group_ids => \@user_group_ids));

    # Used to evaluate permission levels
    my %levels;    # Will be set later

    my @admin_perms = qw( may_publish
      may_checkin_all
      admin_users
      admin_users_limited
      admin_groups
      admin_contribs
      admin_sites
      admin_categories
      admin_categories_ftp
      admin_jobs
      admin_scheduler
      admin_desks
      admin_lists
      admin_delete
      may_view_trash);

    my %admin_perm_access = ();

    # Iterate through each admin_perm
    foreach my $admin_perm (@admin_perms) {
        my $admin_perm_method = $admin_perm;

        if ($admin_perm eq "admin_users_limited") {

            # admin_users_limited is opposite: 0 is higher perm than 1
            %levels = (
                0 => 2,
                1 => 1
            );
        } else {

            # Everything else is normal
            %levels = (
                0 => 1,
                1 => 2
            );
        }

        # Iterate through groups
        foreach my $group (@groups) {
            my $curr_permission_type = $admin_perm_access{$admin_perm};
            $curr_permission_type = "" unless (defined($curr_permission_type));
            my $curr_access_level = $levels{$curr_permission_type} || 0;
            my $permission_type   = $group->$admin_perm_method();
            my $new_access_level  = $levels{$permission_type};

            if ($new_access_level > $curr_access_level) {
                $admin_perm_access{$admin_perm} = $permission_type;
            }
        }
    }

    # Now that we have the table of admin_perm access levels, return results
    return $admin_perm_access{$admin_perm} if ($admin_perm);

    # Return whole table if no specific permission specified
    return %admin_perm_access;
}

###########################
####  PRIVATE METHODS  ####
###########################

# update user_category_permission_cache for users in this group only

sub update_group_user_permissions {
    my $self = shift;

    my @users = pkg('User')->find(group_ids => [$self->group_id]);

    foreach my $user (@users) { $self->add_user_permissions($user) }
}

# Re-build category cache for this category, and descend by recursion
sub rebuild_category_cache_process_category {
    my $self = shift;
    my ($category) = @_;

    # Add categories
    $self->add_category_permissions($category);

    # Descend and recurse
    my @children = $category->children(ignore_user => 1);
    foreach my $category (@children) {
        $self->rebuild_category_cache_process_category($category);
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
        my $level      = $self->$ass_method;
        croak("Invalid $ass_method security level '$level'")
          unless (grep { $level eq $_ } @valid_levels);
    }

    # Check categories
    my %categories = $self->categories;
    while (my ($cat, $level) = each(%categories)) {

        # Make sure permission level makes sense
        croak("Invalid security level '$level' for category_id '$cat'")
          unless (grep { $level eq $_ } @valid_levels);

        # Make sure category exists
        croak("No such category_id '$cat'")
          unless (pkg('Category')->find(category_id => $cat, count => 1));
    }

    # Check desks
    my %desks = $self->desks;
    while (my ($desk, $level) = each(%desks)) {

        # Make sure permission level makes sense
        croak("Invalid security level '$level' for desk_id '$desk'")
          unless (grep { $level eq $_ } @valid_levels);

        # Make sure desk exists
        croak("No such desk_id '$desk'")
          unless (pkg('Desk')->find(desk_id => $desk, count => 1));
    }

    # Is the name unique?
    my $group_id = $self->group_id();
    my $name     = $self->name();

    my $dbh        = dbh();
    my $is_dup_sql = "SELECT group_id from group_permission WHERE name = ? AND group_id != ?";
    my ($dup_id) = $dbh->selectrow_array($is_dup_sql, undef, $name, $group_id);

    # If dup, throw exception
    if ($dup_id) {
        Krang::Group::DuplicateName->throw(message => "duplicate group name", group_id => $dup_id);
    }
}

# Create a new database record for group.  Set group_id in object.
sub insert_new_group {
    my $self = shift;

    my $dbh = dbh();
    $dbh->do("INSERT INTO group_permission (group_id) VALUES (NULL)") || die($dbh->errstr);

    my $group_id = $dbh->{'mysql_insertid'};
    $self->{group_id} = $group_id;

    # Insert group/category permissions
    my $cat_perm_sql = qq/
        INSERT INTO category_group_permission (category_id, group_id, permission_type)
        VALUES (?,?,"edit")
    /;
    my $cat_perm_sth = $dbh->prepare($cat_perm_sql);
    my @root_cats = pkg('Category')->find(ids_only => 1, parent_id => undef);
    foreach my $category_id (@root_cats) {
        $cat_perm_sth->execute($category_id, $group_id);
    }
}

# Static function: Given a SQL query and an array ref with
# query data, send query to Krang log.
sub debug_sql {
    my ($query, $param) = (@_);

    debug(__PACKAGE__ . "::find() SQL: " . $query);
    debug(  __PACKAGE__
          . "::find() SQL ARGS: "
          . join(', ', map { defined $_ ? $_ : 'undef' } @$param));
}

# Given a hash ref with data, instantiate a new Krang::Group object
sub new_from_db {
    my $pkg        = shift;
    my $group_data = shift;

    my $dbh      = dbh();
    my $group_id = $group_data->{group_id};

    # Load categories hash (category_id => security level)
    my $cat_sql =
      "SELECT category_id, permission_type FROM category_group_permission WHERE group_id = ?";
    my $cat_sth = $dbh->prepare($cat_sql);
    $cat_sth->execute($group_id) || die($cat_sth->errstr);
    my %categories = ();
    while (my ($category_id, $permission_type) = $cat_sth->fetchrow_array()) {
        $categories{$category_id} = $permission_type;
    }
    $cat_sth->finish();
    $group_data->{categories} = \%categories;

    # Load desks (desk_id => security level)
    my $desk_sql = "SELECT desk_id, permission_type FROM desk_group_permission WHERE group_id = ?";
    my $desk_sth = $dbh->prepare($desk_sql);
    $desk_sth->execute($group_id) || die($desk_sth->errstr);
    my %desks = ();
    while (my ($desk_id, $permission_type) = $desk_sth->fetchrow_array()) {
        $desks{$desk_id} = $permission_type;
    }
    $desk_sth->finish();
    $group_data->{desks} = \%desks;

    # Bless into object and return
    bless($group_data, $pkg);
    return $group_data;
}

=item may_move_story_from_desk($desk_id)

Convenience method for desk security checks.  If user has 'edit' (check
in/out) permission for C<$desk_id> returns true, otherwise returns false.

=cut

sub may_move_story_from_desk {
    my ($self, $desk_id) = @_;
    return $self->user_desk_permissions($desk_id) eq 'edit' ? 1 : 0;
}

=item may_move_story_to_desk($desk_id)

Convenience method for desk security checks. If user has 'read-only'
(check in) or 'edit' (check in/out) permission for C<$desk_id>, returns
true, otherwise returns false.

=cut

sub may_move_story_to_desk {
    my ($self, $desk_id) = @_;
    return $self->user_desk_permissions($desk_id) ne 'hide' ? 1 : 0;
}

=back

=cut

1;

