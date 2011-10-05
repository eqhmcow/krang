package Krang::Site;

=head1 NAME

Krang::Site - a means to access information on sites

=head1 SYNOPSIS

  use Krang::ClassLoader 'Site';

  # construct object
  my $site = Krang::Site->new(preview_url => 'preview.com',   # required
			      preview_path => 'preview/path/',# required
			      publish_path => 'publish/path/',# required
			      url => 'site.com'); 	      # required

  # saves object to the DB and creates the root category '/' of the site
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
  ( order_desc => 1,		# result ascend unless this flag is set
    limit => 5,       		  # return 5 or less site objects
    offset => 1, 	          # start counting result from the
				  # second row
    order_by => 'url'             # sort on the 'url' field
    preview_path_like => '%bob%', # match sites with preview_path
				  # LIKE '%bob%'
    publish_path_like => '%fred%',
    preview_url => 'preview',	  # match sites where preview_url is
				  # 'preview'
    site_id => 8,
    url_like => '%.com%' );

  # any valid object field can be appended with '_like' to perform a
  # case-insensitive sub-string match on that field in the database

  # returns an array of site objects matching criteria in %params
  my @sites = pkg('Site')->find( %params );

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

N.B - On save(), the root category for the site '/' is created.

=cut

#
# Pragmas/Module Dependencies
##############################
# Pragmas
##########
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

# External Modules
###################
use Carp qw(croak);
use Exception::Class (
    'Krang::Site::Duplicate'  => {fields => 'duplicates'},
    'Krang::Site::Dependency' => {fields => 'category_id'}
);

# Internal Modules
###################
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'UUID';
use Krang::ClassLoader DB   => qw(dbh);
use Krang::ClassLoader Log  => qw/debug affirm assert should shouldnt ASSERT/;
use Krang::ClassLoader Conf => qw(KrangRoot instance);

use File::Spec::Functions qw(catdir);

#
# Package Variables
####################
# Constants
############
# Read-only fields
use constant SITE_RO => qw(site_id site_uuid);

# Read-write fields
use constant SITE_RW => qw(preview_path
  preview_url
  publish_path);

# Globals
##########

# Lexicals
###########
my %site_args = map { $_ => 1 } SITE_RW, 'url';
my %site_cols = map { $_ => 1 } SITE_RO, SITE_RW, 'url';

# Constructor/Accessor/Mutator setup
use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get                              => [SITE_RO],
  get_set                          => [SITE_RW];

sub id_meth   { 'site_id' }
sub uuid_meth { 'site_uuid' }

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

=item * site_uuid (read-only)

Unique ID which identfies a site across different machines when moved
via krang_export/krang_import.

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
    croak(  __PACKAGE__
          . "->init(): The following constructor args are "
          . "invalid: '"
          . join("', '", @bad_args) . "'")
      if @bad_args;

    for (keys %site_args) {
        croak(__PACKAGE__ . "->init(): Required argument '$_' not present.")
          unless exists $args{$_};
    }

    $self->{site_uuid} = pkg('UUID')->new();

    $self->url($args{url}) if exists $args{url};

    $self->hash_init(%args);

    return $self;
}

=item * $success = $site->delete()

=item * $success = Krang::Site->delete( $site_id )

Instance or class method that deletes the given site from the database and its
root category that gets instantiated on save().  It croaks if any categories
reference this site other than '/'.  It returns '1' following a successful
deletion.

This method's underlying call to dependent_check() may result in a
Krang::Site::Dependency exception if an object in the system is found that
relies upon the Site in question.

N.B. - This call will result in the deletion of the Site's root category.

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->{site_id};

    # get object if we don't have it
    ($self) = pkg('Site')->find(site_id => $id);

    # check for references to this site
    $self->dependent_check();

    # delete root category
    my ($root) = pkg('Category')->find(
        dir     => '/',
        site_id => $id
    );
    $root->delete() if $root; # only need to do this if the category hasn't already been deleted

    # remove record from the site table
    my $dbh = dbh();
    $dbh->do("DELETE FROM site WHERE site_id = ?", undef, ($id));

    # verify deletion was successful
    return pkg('Site')->find(site_id => $id) ? 0 : 1;
}

=item * $site->dependent_check()

=item * Krang::Site->dependent_check( $site_id )

Class or instance method that should be called before attempt to delete a Site.
If any categories are found that depend rely upon this Site, then a
Krang::Site::Dependency exception is thrown, otherwise, 0 is returned.

The exception's 'category_id' field contains a list of the ids of depending
categories.  You might wish to handle the exception thusly:

 eval {$site->dependent_check()};
 if ($@ and $@->isa('Krang::Site::Dependency')) {
     croak("This Site cannot be deleted.  Categories with the following" .
	   " ids depend upon it: " . join(",", $@->category_id) . "\n");
 }

N.B. - the root category of the site is excluded from this lookup.

=cut

sub dependent_check {
    my $self = shift;
    my $id = shift || $self->{site_id};
    my ($category_id, @ids);

    my $dbh = dbh();
    my $sth =
      $dbh->prepare("SELECT category_id FROM category WHERE dir != '/' AND " . "site_id = ?");
    $sth->execute($id);
    $sth->bind_col(1, \$category_id);
    push @ids, $category_id while $sth->fetch();

    Krang::Site::Dependency->throw(
        message     => 'Site cannot be deleted. ' . 'Dependent categories found.',
        category_id => \@ids
    ) if @ids;

    return 0;
}

=item * $site->duplicate_check()

This method checks the database to see if any existing site objects
possess the same URLs any of the same values as the object in memory.
If this is the case, a Krang::Site::Duplicate exception is thrown,
otherwise, 0 is returned.

=cut

sub duplicate_check {
    my $self = shift;
    my $dbh  = dbh();
    my $id   = $self->{site_id};

    # setup query
    my @params = ($self->{url});
    my $query  = "SELECT 1 FROM site WHERE url = ?";
    if ($id) {
        $query .= " AND site_id != ?";
        push @params, $id;
    }

    my ($exists) = $dbh->selectrow_array($query, undef, @params);
    Krang::Site::Duplicate->throw(
        message => "A site with the URL '$self->{url}' already exists in the database.")
      if $exists;

    # no dup found
    return 0;
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

=item * site_id

=item * site_uuid

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
    my $limit    = delete $args{limit}    || '';
    my $offset   = delete $args{offset}   || '';
    my $order_by = delete $args{order_by} || 'url';

    # set search fields
    my $count    = delete $args{count}    || '';
    my $ids_only = delete $args{ids_only} || '';

    # set bool to determine whether to use $row or %row for binding below
    my $single_column = $ids_only || $count ? 1 : 0;

    croak(  __PACKAGE__
          . "->find(): 'count' and 'ids_only' were supplied. "
          . "Only one can be present.")
      if ($count && $ids_only);

    $fields =
      $count
      ? 'count(*)'
      : ($ids_only ? 'site_id' : join(", ", keys %site_cols));

    # set up WHERE clause and @params, croak unless the args are in
    # SITE_RO or SITE_RW
    my @invalid_cols;
    for my $arg (keys %args) {
        my $like = 1 if $arg =~ /_like$/;
        (my $lookup_field = $arg) =~ s/^(.+)_like$/$1/;

        push @invalid_cols, $arg
          unless exists $site_cols{$lookup_field}
              || $arg eq 'simple_search';

        if ($arg eq 'site_id' && ref $args{site_id} eq 'ARRAY' && @{$args{site_id}} > 0) {
            my $tmp = join(" OR ", map { "site_id = ?" } @{$args{site_id}});
            $where_clause .= " ($tmp)";
            push @params, @{$args{site_id}};
        } elsif ($arg eq 'simple_search') {
            my @words = split(/\s+/, $args{simple_search});
            for my $word (@words) {
                my $numeric = $word =~ /^\d+$/ ? 1 : 0;
                if ($where_clause) {
                    $where_clause .=
                      $numeric
                      ? " AND site_id LIKE ?"
                      : " AND (preview_path LIKE ? OR preview_url LIKE ? OR "
                      . "publish_path LIKE ? OR url LIKE ?)";
                } else {
                    $where_clause =
                      $numeric
                      ? "site_id LIKE ?"
                      : "(preview_path LIKE ? OR preview_url LIKE ? OR "
                      . "publish_path LIKE ? OR url LIKE ?)";
                }
                my $count = $numeric ? 1 : 4;
                push @params, "%" . $word . "%" for (1 .. $count);
            }
        } else {
            my $and = defined $where_clause && $where_clause ne '' ? ' AND' : '';
            if (not defined $args{$arg}) {
                $where_clause .= "$and $lookup_field IS NULL";
            } else {
                $where_clause .=
                  $like
                  ? "$and $lookup_field LIKE ?"
                  : "$and $lookup_field = ?";
                push @params, $args{$arg};
            }
        }
    }

    croak(
        "The following passed search parameters are invalid: '" . join("', '", @invalid_cols) . "'")
      if @invalid_cols;

    # construct base query
    my $query = "SELECT $fields FROM site";

    # add WHERE and ORDER BY clauses, if any
    $query .= " WHERE $where_clause"        if $where_clause;
    $query .= " ORDER BY $order_by $ascend" if $order_by;

    # add LIMIT clause, if any
    if ($limit) {
        $query .= $offset ? " LIMIT $offset, $limit" : " LIMIT $limit";
    } elsif ($offset) {
        $query .= " LIMIT $offset, 18446744073709551615";
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
        $sth->bind_columns(\(@$row{@{$sth->{NAME_lc}}}));
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

Saves the contents of the site object in memory to the database and creates its
root category.  The method also updates the urls of categories that reference
it via update_child_categories() if its 'url' field has changed since the last
save.

The method croaks if the save would result in a duplicate site object (i.e.
if the object has the same path or url as another object).  It also croaks if
its database query affects no rows in the database.

=cut

sub save {
    my $self        = shift;
    my $id          = $self->{site_id} || '';
    my @save_fields = grep { $_ ne 'site_id' } keys %site_cols;

    # flag to force update of child categories
    my $update = $self->{url} ne $self->{_old_url} ? 1 : 0;

    # check for duplicates - an exception is thrown if necessary...
    $self->duplicate_check();

    my $query;
    if ($id) {
        $query =
          "UPDATE site SET " . join(", ", map { "$_ = ?" } @save_fields) . " WHERE site_id = ?";
    } else {
        $query =
            "INSERT INTO site ("
          . join(',', @save_fields)
          . ") VALUES (?"
          . ", ?" x (scalar @save_fields - 1) . ")";
    }

    # bind parameters
    my @params = map { $self->{$_} } @save_fields;

    # need site_id for updates
    push @params, $id if $id;

    my $dbh = dbh();

    # croak if no rows are affected
    croak(  __PACKAGE__
          . "->save(): Unable to save site object "
          . ($id ? "id '$id' " : '')
          . "to the DB.")
      unless $dbh->do($query, undef, @params);

    unless ($id) {
        $self->{site_id} = $dbh->{mysql_insertid};

        # create root category if it doesn't exist...
        my $category = pkg('Category')->new(
            dir     => '/',
            site_id => $self->{site_id}
        );
        $category->save();
    }

    # update category urls if necessary
    if ($update) {

        # Rename templates directory (if it exists)
        my $current_instance        = pkg('Conf')->instance;
        my $base_template_path      = catdir(KrangRoot, "data", "templates", $current_instance);
        my $template_directory_path = catdir($base_template_path, $self->{_old_url});
        debug("template_directory_path = '$template_directory_path'");
        if (-d $template_directory_path) {
            my $new_template_path = catdir($base_template_path, $self->{url});
            debug("Renaming '$template_directory_path' to '$new_template_path'");
            rename($template_directory_path, $new_template_path)
              || die("Can't rename '$template_directory_path' to '$new_template_path': $!");
        }

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
    my $id   = $self->{site_id};
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
        should(scalar @ids, scalar pkg('Category')->find(category_id => \@ids))
          if ASSERT;
        $_->update_child_urls($self) for pkg('Category')->find(category_id => \@ids);
    }

    return 1;
}

=item * $url = $site->url()

=item * $site = $site->url( $url )

Instance method that gets and sets the object 'url' field.  When called as a
setter, the '_old_url' is updated as well.

=cut

sub url {
    my $self = shift;
    return $self->{url} unless @_;
    if ($_[0]) {
        my $val = exists $self->{url} && $self->{url} ne '' ? $self->{url} : $_[0];
        $self->{_old_url} = $val;
        $self->{url}      = $_[0];
    }
    return $self;
}

=item * C<< $site->serialize_xml(writer => $writer, set => $set) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self,   %args) = @_;
    my ($writer, $set)  = @args{qw(writer set)};
    local $_;

    # open up <site> linked to schema/site.xsd
    $writer->startTag(
        'site',
        "xmlns:xsi"                     => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation" => 'site.xsd'
    );

    $writer->dataElement($_, $self->$_)
      for qw(site_id site_uuid url preview_url publish_path preview_path);
    $writer->endTag('site');
}

=item * C<< $site = Krang::Site->deserialize_xml(xml => $xml, set => $set, no_update => 0, skip_update => 0) >>

Deserialize XML.  See Krang::DataSet for details.

If an incoming site has the same URL as an existing site then the
incoming site is skipped.  This change from the usual
deserialize_xml() behavior was made on the theory that preview_path
and publish_path are likely to vary between alpha, beta and production
instances of the same site.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set, $no_update, $skip_update) = @args{qw(xml set no_update skip_update)};

    # parse it up
    my $data = pkg('XML')->simple(
        xml           => $xml,
        suppressempty => 1
    );

    # is there an existing object?
    my $site;

    # start with UUID lookup
    if (not $args{no_uuid} and $data->{site_uuid}) {
        ($site) = $pkg->find(site_uuid => $data->{site_uuid});

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A site object with the UUID '$data->{site_uuid}' already"
              . " exists and no_update is set.")
          if $site and $no_update;
    }

    # proceed to URL lookup if no dice
    unless ($site or $args{uuid_only}) {
        ($site) = pkg('Site')->find(url => $data->{url});

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A site object with the url '$data->{url}' already "
              . "exists and no_update is set.")
          if $site and $no_update;
    }

    if ($site) {
        return $site if $skip_update;

        # update URLs, ignore paths (these can change now with UUID matches)
        $site->url($data->{url});
        $site->preview_url($data->{preview_url});
    } else {

        # create a new site
        $site = pkg('Site')->new(map { ($_, $data->{$_}) } keys %site_args);
    }

    # preserve UUID if available
    $site->{site_uuid} = $data->{site_uuid}
      if $data->{site_uuid} and not $args{no_uuid};

    $site->save();

    return $site;
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
