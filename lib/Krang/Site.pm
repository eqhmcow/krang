package Krang::Site;

=head1 NAME

Krang::Site - a means access to information on sites

=head1 SYNOPSIS

  use Krang::Site;

  # construct object
  my $site = Krang::Site->new(preview_url => 'preview.com',   # optional
			      publish_url => 'publish.com',   # optional
			      preview_path => 'preview/path/',# optional
			      publish_path => 'publish/path/',# required
			      url => 'site.com'); 	      # required

  # saves object to the DB
  $site->save();

  # get or set the site objects fields
  my $id = $site->site_id();

  my $path = $site->preview_path() || $site->publish_path();

  $site->preview_path( $path . '_bob' );

  my $url = $site->preview_url() || $site->publish_url() || $site->url();

  $url =~ s/foo/bar/;

  $site->url( $url );

  # delete the site from the database
  $site->delete();

  # a hash of search parameters
  my %params =
  ( ascend => 1,      		  # sort results in ascending order
    limit => 5,       		  # return 5 or less site objects
    offset => 1, 	          # start counting result from the
				  # second row
    order_by => 'url'             # sort on the 'url' field
    preview_path_like => '%bob%', # match sites with preview_path
				  # LIKE '%bob%'
    publish_path_like => '%fred%',
    preview_url => 'preview',	  # match sites where preview_url is
				  # 'preview'
    publish_url => 'publish',
    site_id => 8,
    url_like => '%.com%' );

  # any valid object field can be appended with '_like' to perform a
  # case-insensitive sub-string match on that field in the database

  # returns an array of site objects matching criteria in %params
  my @sites = Krang::Site->find( %params );

=head1 DESCRIPTION

This module serves as a means of adding, deleting, accessing site objects for a
given Krang instance.  Template objects, at present, do little other than act
as a means to determine the urls and path associated with a site.

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

# Internal Modules
###################
use Krang;
use Krang::DB qw(dbh);

#
# Package Variables
####################
# Constants
############

# Globals
##########

# Lexicals
###########



=head1 INTERFACE

=head2 FIELDS

Access to fields for this object is provided my Krang::MethodMaker.  The value
of fields can be obtained and set in the following fashion:

 $value = $site->field_name();
 $site->field_name( $some_value );

The available fields for a site object are:

=over 4

=item * preview_path

Path under which the media and stories of this site will be output for preview.

=item * preview_url

URL relative to which one is redirected after the preview output of a media
object or story is generated.

=item * publish_path

Path under which the media and stories are published.

=item * publish_url

URL relative to which one is redirected after a media object or story is
published.

=item * site_id (read-only)

Integer which identifies the database rows associated with this site object.

=item * url

Base URL where site content is found.

=back

=head2 METHODS

=over 4

=item * $site = Krang::Site->new( %params )

Constructor for the module that relies on Krang::MethodMaker.  Validation of
'%params' is performed in init().  The valid fields for the hash are:

=over 4

=item * preview_path

=item * preview_url

=item * publish_path

=item * publish_url

=item * url

=back

=cut

# validates arguments passed to new(), see Class::MethodMaker
# the method croaks if an invalid key is found in the hash passed to new()
sub init {
    my $self = shift;
    my %args = shift;

    return $self;
}


=item * $success = $site->delete()

=item * $success = Krang::Site->delete( $site_id )

Instance or class method that deletes the given site from the database.  It
returns '1' following a successful deletion.

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->{site_id};
    
    return 1;
}


=item * $site = $site->save()

Saves the contents of the site object in memory to the database.

The method croaks if the save would result in a duplicate site object (i.e.
if the object has the same path or url as another object).  It also croaks if
its database query affects no rows in the database.

=cut

sub save {
    my $self = shift;

    return $self;
}


=back

=head1 TO DO

Lots.

=head1 SEE ALSO

L<Krang::>, L<Krang::DB>

=cut


my $poem = <<END;
END
