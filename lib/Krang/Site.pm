package Krang::Site;

=head1 NAME

Krang::Site - a means to access information on sites

=head1 SYNOPSIS

  use Krang::Site;

  # construct object
  my $site = Krang::Site->new(preview_url => 'preview.com',   # required
			      preview_path => 'preview/path/',# required
			      publish_path => 'publish/path/',# required
			      url => 'site.com'); 	      # required

  # saves object to the DB
  $site->save();

  # getters
  my $id = $site->site_id();			# undef until save()
  my $path = $site->preview_path();
  my $path = $site->publish_path();
  my $url = $site->preview_url();
  my $url = $site->url();

  # setters
  $site->preview_path( $new_preview_path );
  $site->publish_path( $new_publish_path );
  $site->url( $url );

  # delete the site from the database
  $site->delete();

  # a hash of search parameters
  my %params =
  ( order_desc => 'asc',      	  # sort results in ascending order
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

A site is the basic organizational unit within a Krang instance.  A site may
correspond to a web-site but only necessarily maps to a unique URL.  Content
within the site is stored within categories; see L<Krang::Category>.

On preview, site output is written to paths under 'preview_path' and then the
user is redirected to 'preview_url' - it is the same for 'publish_path' and
'url' upon publishing an asset.

This module serves as a means of adding, deleting, accessing site objects for a
given Krang instance.  Site objects, at present, do little other than act
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
use Carp qw(croak);

# Internal Modules
###################
use Krang;
use Krang::Category;
use Krang::DB qw(dbh);
use Krang::Log qw/affirm assert should shouldnt ASSERT/;

#
# Package Variables
####################
# Constants
############
# Read-only fields
use constant SITE_RO => qw(site_id);

# Read-write fields
use constant SITE_RW => qw(preview_path
			   preview_url
			   publish_path
			   url);

# Globals
##########

# Lexicals
###########
my %site_args = map {$_ => 1} SITE_RW;
my %site_cols = map {$_ => 1} SITE_RO, SITE_RW;

# Constructor/Accessor/Mutator setup
use Krang::MethodMaker	new_with_init => 'new',
			new_hash_init => 'hash_init',
			get => [SITE_RO],
			get_set => [SITE_RW];


=head1 INTERFACE

=head2 FIELDS

Access to fields for this object is provided my Krang::MethodMaker.  The value
of fields can be obtained and set in the following fashion:

 $value = $site->field_name();
 $site->field_name( $some_value );

The available fields for a site object are:

=over 4

=item * preview_path

Full filesystem path under which the media and stories of this site will be
output for preview.

=item * preview_url

URL relative to which one is redirected after the preview output of a media
object or story is generated.  The document root of this server is the value
of 'preview_path'.

=item * publish_path

Full filesystem path under which the media and stories are published.

=item * site_id (read-only)

Integer which identifies the database rows associated with this site object.

=item * url

Base URL where site content is found.  Categories and consequently media and
stories will form their URLs based on this value.

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

=item * url

=back

=cut

# validates arguments passed to new(), see Class::MethodMaker, sets '_old_url'
# the method croaks if an invalid key is found in the hash passed to new() or
# if 'url' and 'publish_path' haven't been provided...
sub init {
    my $self = shift;
    my %args = @_;
    my @bad_args;

    for (keys %args) {
        push @bad_args, $_ unless exists $site_args{$_};
    }
    croak(__PACKAGE__ . "->init(): The following constructor args are " .
          "invalid: '" . join("', '", @bad_args) . "'") if @bad_args;

    for (SITE_RW) {
        croak(__PACKAGE__ . "->init(): Required argument '$_' not present.")
          unless exists $args{$_};
    }

    $self->hash_init(%args);

    # set field to track changes to 'url'
    $self->{_old_url} = $self->{url};

    return $self;
}


=item * $success = $site->delete()

=item * $success = Krang::Site->delete( $site_id )

Instance or class method that deletes the given site from the database.  It
croaks if any categories reference this site.  It returns '1' following a
successful deletion.

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->{site_id};

    # check for references to this site
    my %info = $id ? $self->dependent_check() :
      Krang::Site->dependent_check();

    croak(__PACKAGE__ . "->delete(): Category(ies): [" . join(',', keys %info)
          . "] rely on this site.")
      if keys %info;

    my $dbh = dbh();
    $dbh->do("DELETE FROM site WHERE site_id = ?", undef, ($id));

    return 1;
}


=item * %info = $site->dependent_check()

=item * %info = Krang::Site->dependent_check( $site_id )

Class or instance method that returns a hash of category ids relying upon the
given site object.

=cut

sub dependent_check {
    my $self = shift;
    my $id = shift || $self->{site_id};
    my ($category_id, %info);

    my $dbh = dbh();
    my $sth =
      $dbh->prepare("SELECT category_id FROM category WHERE site_id = ?");
    $sth->execute(($id));
    $sth->bind_col(1, \$category_id);
    $info{$category_id} = 1 while $sth->fetch();

    return %info;
}


=item * %info = $site->duplicate_check()

This method checks the database to see if any existing site objects possess any
of the same values as the one in memory.  If this is the case an array
containing the 'site_id' and the name of the duplicate field is returned
otherwise the array will be empty.

=cut

sub duplicate_check {
    my $self = shift;
    my $id = $self->{site_id};
    my (@fields, %info, @params, @wheres);

    for (keys %site_cols) {
        push @fields, $_;
        push @wheres, "$_ = ?";
        push @params, $self->{$_};
    }

    my $query = "SELECT " . join(",", @fields).
      " FROM site WHERE (" . join(" OR ", @wheres) . ")";

    if ($id) {
        $query .= " AND site_id != ?";
        push @params, $_;
    }

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);

    my $row;
    $sth->bind_columns(\(@$row{@{$sth->{NAME_lc}}}));
    while ($sth->fetch()) {
        for (keys %$row) {
            if (exists $self->{$_} && exists $row->{$_}
                && $self->{$_} eq $row->{$_}) {
                $info{$row->{site_id}} = $_;
            }
        }
    }
    $sth->finish();

    return %info;
}


=item * @sites = Krang::Site->find( %params )

=item * @sites = Krang::Site->find( site_id => [1, 1, 2, 3, 5] )

=item * @site_ids = Krang::Site->find( ids_only => 1, %params )

=item * $count = Krang::Site->find( count => 1, %params )

Class method that returns an array of site objects, site ids, or a count.
Case-insensitive sub-string matching can be performed on any valid field by
passing an argument like: "fieldname_like => '%$string%'" (Note: '%'
characters must surround the sub-string).  The valid search fields are:

=over 4

=item * preview_path

=item * preview_url

=item * publish_path

=item * publish_url

=item * site_id

=item * url

=back

Additional criteria which affect the search results are:

=over 4

=item * count

If this argument is specified, the method will return a count of the sites
matching the other search criteria provided.

=item * ids_only

Returns only site ids for the results found in the DB, not objects.

=item * limit

Specify this argument to determine the maximum amount of site object or
site ids to be returned.

=item * offset

Sets the offset from the first row of the results to return.

=item * order_by

Specify the field by means of which the results will be sorted.  By default
results are sorted with the 'site_id' field.

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
    my $order_by = delete $args{order_by} || 'site_id';

    # set search fields
    my $count = delete $args{count} || '';
    my $ids_only = delete $args{ids_only} || '';

    # set bool to determine whether to use $row or %row for binding below
    my $single_column = $ids_only || $count ? 1 : 0;

    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.") if ($count && $ids_only);

    $fields = $count ? 'count(*)' :
      ($ids_only ? 'site_id' : join(", ", keys %site_cols));

    # set up WHERE clause and @params, croak unless the args are in
    # SITE_RO or SITE_RW
    my @invalid_cols;
    for my $arg (keys %args) {
        my $like = 1 if $arg =~ /_like$/;
        ( my $lookup_field = $arg ) =~ s/^(.+)_like$/$1/;

        push @invalid_cols, $arg unless exists $site_cols{$lookup_field};

        if ($arg eq 'site_id' && ref $args{$arg} eq 'ARRAY') {
            my $tmp = join(" OR ", map {"site_id = ?"} @{$args{$arg}});
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
    my $query = "SELECT $fields FROM site";

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
    my ($row, @sites);

    # bind fetch calls to $row or %$row
    # a possibly insane micro-optimization :)
    if ($single_column) {
        $sth->bind_col(1, \$row);
    } else {
        $sth->bind_columns(\( @$row{@{$sth->{NAME_lc}}} ));
    }

    # construct site objects from results
    while ($sth->fetchrow_arrayref()) {
        # if we just want count or ids
        if ($single_column) {
            push @sites, $row;
        } else {
            # set _old_url
            $row->{_old_url} = $row->{url};
            push @sites, bless({%$row}, $self);
        }
    }

    # finish statement handle
    $sth->finish();

    # return number of rows if count, otherwise an array of site ids or objects
    return $count ? $sites[0] : @sites;
}


=item * $site = $site->save()

Saves the contents of the site object in memory to the database.  The method
also updates the urls of categories that reference it via
update_child_categories() if its 'url' field has changed since the last save.

The method croaks if the save would result in a duplicate site object (i.e.
if the object has the same path or url as another object).  It also croaks if
its database query affects no rows in the database.

=cut

sub save {
    my $self = shift;
    my $id = $self->{site_id} || '';
    my @save_fields = grep {$_ ne 'site_id'} keys %site_cols;

    # flag to force update of child categories
    my $update = $self->{url} ne $self->{_old_url} ? 1 : 0;

    # check for duplicates
    my %info = $self->duplicate_check();
    croak(__PACKAGE__ . "->save(): The following duplicates exits:\n\t" .
          join("\n\t", map {"Site id '$_': $info{$_}"} keys %info))
      if keys %info;

    my $query;
    if ($id) {
        $query = "UPDATE site SET " .
          join(", ", map {"$_ = ?"} @save_fields) .
            " WHERE site_id = ?";
    } else {
        $query = "INSERT INTO site (" . join(',', @save_fields) .
          ") VALUES (?" . ", ?" x (scalar @save_fields - 1) . ")";
    }

    # bind parameters
    my @params = map {$self->{$_}} @save_fields;

    # need site_id for updates
    push @params, $id if $id;

    my $dbh = dbh();

    # croak if no rows are affected
    croak(__PACKAGE__ . "->save(): Unable to save site object " .
          ($id ? "id '$id' " : '') . "to the DB.")
      unless $dbh->do($query, undef, @params);

    $self->{site_id} = $dbh->{mysql_insertid} unless $id;

    # update category urls if necessary
    if ($update) {
        $self->update_child_categories();
        $self->{_old_url} = $self->{url};
    }

    return $self;
}


=item * $success = $site->update_child_categories()

This method updates child categories' urls provided the 'url' field of the
object has recently been changes (see save()).  It returns 1 on the success of
the update.

=cut

sub update_child_categories {
    my $self = shift;
    my $id = $self->{site_id};
    my ($category_id, @ids);

    my $query = <<SQL;
SELECT category_id
FROM category
WHERE site_id = ?
SQL

    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(($id));
    $sth->bind_columns(\$category_id);
    push @ids, $category_id while $sth->fetch;
    $sth->finish();

    # update all the children :)
    if (@ids) {
        should(scalar @ids, scalar Krang::Category->find(category_id => \@ids))
          if ASSERT;
        $_->update_child_urls()
          for Krang::Category->find(category_id => \@ids);
    }

    return 1;
}


=back

=head1 TO DO

=head1 SEE ALSO

L<Krang>, L<Krang::DB>

=cut


my $quip = <<END;
Democracy is the theory that holds that the common people know what they want,
and deserve to get it good and hard.

--H.L. Mencken
END
