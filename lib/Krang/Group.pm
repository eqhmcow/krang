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
                                 categories    => { 1 => 'read-only', 
                                                    2 => 'edit', 
                                                   23 => 'hide' },
                                 desks         => {  NOT YET IMPLEMENTED  },
                                 applications  => {  NOT YET IMPLEMENTED  },
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
  my %applications     = $group->applications();


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


# Constructor/Accessor/Mutator setup
use Krang::MethodMaker ( new_with_init => 'new',
                         new_hash_init => 'hash_init',
                         get => [ "group_id" ],
                         get_set => [ qw( name
                                          may_publish
                                          admin_users
                                          admin_users_limited
                                          admin_groups
                                          admin_contribs
                                          admin_sites
                                          admin_categories
                                          admin_jobs
                                          admin_desks
                                          admin_prefs ) ],
                         hash => [ qw( categories
                                       desks 
                                       applications ) ] );


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
  * applications (hash)  - Application class ID to security level

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
                    categories => {},
                    desks => {},
                    applications => {},
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

##  REMOVE  ###########
use constant FIELDS => ();

sub find {
    my $self = shift;
    my %args = @_;


    # Check for invalid args and croak() if any
    my @valid_find_params = qw(
                               order_desc
                               name
                               name_like
                               limit
                               offset
                               simple_search
                               count
                               only_ids
                               group_id
                              );

    foreach my $arg (keys(%args)) {
        croak ("Invalid find arg '$arg'")
          unless (grep { $arg eq $_ } @valid_find_params);
    }

    croak("Krang::Group->find() not yet implemented");

    my $dbh = dbh();
    my @where = ();
    my @contrib_object = ();
    my $where_string = "";

    my $order_desc = $args{'order_desc'} ? 'desc' : 'asc';    
    $args{order_by} ||= 'last,first';
    my $order_by =  join(',', 
                         map { "$_ $order_desc" } 
                           split(',', $args{'order_by'}));
    my $limit = $args{'limit'} ? $args{'limit'} : undef;
    my $offset = $args{'offset'} ? $args{'offset'} : 0;

    foreach my $key (keys %args) {
        if ( ($key eq 'contrib_id') || ($key eq 'first') || ($key eq 'last') ) {
            push @where, $key;
        }
    }

    $where_string = join ' and ', (map { "$_ = ?" } @where);

    # exclude_contrib_ids: Specifically exclude contribs with IDs in this set
    if ($args{'exclude_contrib_ids'}) {
        my $exclude_contrib_ids_sql_set = "'".  join("', '", @{$args{'exclude_contrib_ids'}})  ."'";

        # Append to SQL where clause
        $where_string .= " and " if ($where_string);
        $where_string .= "contrib_id NOT IN ($exclude_contrib_ids_sql_set)";
    }

    # full_name: add like search on first, last, middle for all full_name words
    if ($args{'full_name'}) {
        my @words = split(/\s+/, $args{'full_name'});
        foreach my $word (@words) {
            if ($where_string) {
               $where_string .= " and concat(first,' ',middle,' ',last) like ?"; 
            } else {
                $where_string = "concat(first,' ',middle,' ',last) like ?";
            }
            push (@where, $word);
            $args{$word} = "%$word%";
        }
    } 
    
    # simple_search: add like search on first, last, middle for all simple_search words
    if ($args{'simple_search'}) {
        my @words = split(/\s+/, $args{'simple_search'});
        foreach my $word (@words) {
            if ($where_string) {
               $where_string .= " and concat(first,' ',middle,' ',last) like ?"; 
            } else {
                $where_string = "concat(first,' ',middle,' ',last) like ?";
            }
            push (@where, $word);
            $args{$word} = "%$word%";
        }
    } 
    
    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*)';
    } elsif ($args{'only_ids'}) {
        $select_string = 'contrib_id';
    } else {
        $select_string = join(',', FIELDS);
    }

    my $sql = "select $select_string from contrib";
    $sql .= " where ".$where_string if $where_string;
    $sql .= " order by $order_by ";
    
    # add limit and/or offset if defined
    if ($limit) {
       $sql .= " limit $offset, $limit";
    } elsif ($offset) {
        $sql .= " limit $offset, -1";
    }

    my $sth = $dbh->prepare($sql);
    $sth->execute(map { $args{$_} } @where) || croak("Unable to execute statement $sql");
    while (my $row = $sth->fetchrow_hashref()) {
        my $obj;
        if ($args{'count'}) {
            return $row->{'count(*)'};
        } elsif ($args{'only_ids'}) {
            $obj = $row->{contrib_id};
        } else {
            $obj = bless {}, $self;
            %$obj = %$row;

            # load contrib_type ids
            my $result = $dbh->selectcol_arrayref(
                          'SELECT contrib_type_id FROM contrib_contrib_type
                           WHERE contrib_id = ?', undef, $obj->{contrib_id});
            $obj->{contrib_type_ids} = $result || [];
        }
        push (@contrib_object,$obj);
    }
    $sth->finish();
    return @contrib_object;
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



=back


=head1 AUTHOR

Jesse Erlbaum <jesse@erlbaum.net>

=cut


1;

