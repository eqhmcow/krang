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
                                 desks      => {  NOT YET IMPLEMENTED  },
                                 assets     => {  NOT YET IMPLEMENTED  },
                                 may_publish         => 1,
                                 admin_users         => 1,
                                 admin_users_limited => 1,
                                 admin_groups        => 1,
                                 admin_contribs      => 1,
                                 admin_sites         => 1,
                                 admin_categories    => 1,
                                 admin_jobs          => 1,
                                 admin_desks         => 1,
                                 admin_prefs         => 1 );


  # Save group
  $group->save();


  # Get group ID
  my $group_id = $self->group_id();


  # Delete group
  $group->delete();


  # Retrieve an existing group
  my ($group) = Krang::Group->find( group_id => 123 );


  # Find groups by exact name
  my @groups = Krang::Group->find( name => 'Boat Editors' );


  # Find groups by name pattern
  my @groups = Krang::Group->find( name_like => '%editor%' );


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
  my %categories       = $group->categories();
  my %desks            = $group->desks();
  my %assets     = $group->assets();


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
                           admin_prefs );

# Constructor/Accessor/Mutator setup
use Krang::MethodMaker ( new_with_init => 'new',
                         new_hash_init => 'hash_init',
                         get => [ "group_id" ],
                         get_set => [ FIELDS ],
                         hash => [ qw( categories
                                       desks 
                                       assets ) ] );


=item new()

  my $group = Krang::Group->new();

This method returns a new Krang::Group object.  You may pass a hash
into new() containing initial values for the object properties.  These
properties are:

  * name (scalar)  - Name of this group
  * may_edit_user (scalar)  - "1" or "0"
  * may_publish (scalar)  - "1" or "0"
  * categories (hash)  - Map category ID to security level
  * desks (hash)  - Map desk ID to security level
  * assets (hash)  - Asset ID to security level

Security levels may be "edit", "read-only", or "hide".

=cut

sub init {
    my $self = shift;
    my %args = ( @_ );

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
                    categories          => {},
                    desks               => {},
                    assets              => {},
                   );

    # finish the object
    $self->hash_init(%defaults, %args);

    # Set default group_id
    $self->{group_id} = 0;

    return $self;
}


=item find()

Retrieve Krang::Group objects from database.

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

    die ("Invalid category_id '$category_id'") unless ($category_id and $category_id =~ /^\d+$/);

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

    # Load categories hash (category_id => security level)

    # Load desks (desk_id => security level)

    # Load assets (asset_id => security level)

    # Bless into object and return
    bless ($group_data, $pkg);
    return $group_data;
}


=back


=head1 AUTHOR

Jesse Erlbaum <jesse@erlbaum.net>

=cut


1;

