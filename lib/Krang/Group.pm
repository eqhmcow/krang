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
                                 may_edit_user => 0,
                                 may_publish   => 1,
                                 categories    => { 1 => 'read-only', 
                                                    2 => 'edit', 
                                                   23 => 'hide' },
                                 desks         => {  NOT YET IMPLEMENTED  },
                                 applications  => {  NOT YET IMPLEMENTED  } );


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
  my $name          = $group->name();
  my $may_edit_user = $group->may_edit_user();
  my $may_publish   = $group->may_publish();
  my %categories    = $group->categories();
  my %desks         = $group->desks();
  my %applications  = $group->applications();


  # Category permissions cache management
  Krang::Group->add_catagory_cache($category_id);
  Krang::Group->delete_catagory_cache($category_id);
  Krang::Group->rebuild_catagory_cache();


=head1 DESCRIPTION

Krang::Group provides access to manipulate Krang's permission groups.
These groups control authorization within Krang as documented in the file 
F<krang/docs/permissions.pod>.


=head1 INTERFACE

The following methods are provided by Krang::Group.

=over 4

=cut


# Constructor/Accessor/Mutator setup
use Krang::MethodMaker ( new_with_init => 'new',
                         new_hash_init => 'hash_init',
                         get => [ "group_id" ],
                         get_set => [ qw( name
                                          may_edit_user
                                          may_publish ) ],
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
                    may_edit_user => "0",
                    may_publish => "0",
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



=back


=head1 AUTHOR

Jesse Erlbaum <jesse@erlbaum.net>

=cut


1;

