package Krang::Template;

=head1 NAME

Krang::Template - Interface for managing template objects

=head1 SYNOPSIS

 # create a new template
 my $template = pkg('Template')->new(category    => $category,
                                     content     => '<tmpl_var test>',
                                     filename    => 'test.tmpl');

 # save contents of the object to the DB.
 $template->save();

 # put the object back into circulation for other users
 $template->checkin();

 # checkout object to work on it
 $template->checkout();

 # saves to the db again, increments version field of the object
 $template->save();

 # use this template for testing, will override deployed versions of the
 # same template
 $template->mark_for_testing();

 # no longer use this template for testing
 $template->unmark_for_testing();

 # Mark the template as having been deployed to the Krang publish path.
 # unsets testing flag in the database
 $template->mark_as_deployed();

 # Mark the template as not existing in the publish path.
 # unsets deployed, deploy_version, deploy_date.
 $template->mark_as_undeployed();

 # reverts to template revision specified by $version
 $template->revert( $version );

 # deploy template
 $template->deploy

 # remove all references to the object in the template and
 # template_version tables
 $template->delete();

 # returns array of template objects matching criteria in %params
 my @templates = pkg('Template')->find( %params );

 # Get permissions for this object
 $template->may_see() || croak("Not allowed to see");
 $template->may_edit() || croak("Not allowed to edit");


=head1 DESCRIPTION

Templates determine the form of this system's output.  This module provides a
means to check in, check out, edit, revert, save, and search Template objects.

A template is either associated with an element class and hence determines
its formatting or it may serve as some manner of miscellaneous utility
whether formatting or otherwise.  Template data, i.e. the 'content' field, is,
at present, intended to be in HTML::Template format.  All template filenames
will end in the extension '.tmpl'.  Users have the ability to revert to any
previous version of a template.

This module interfaces or will interface with Krang::CGI::Template,
Krang::Burner, the FTP interface, and the SOAP interface.

=cut

# Pragmas
##########
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

# External Module Dependencies
###############################
use Carp qw(verbose croak);
use Exception::Class (
    'Krang::Template::Checkout'             => {fields => [qw/template_id user_id/]},
    'Krang::Template::DuplicateURL'         => {fields => 'template_id'},
    'Krang::Template::NoCategoryEditAccess' => {fields => 'category_id'},
    'Krang::Template::NoEditAccess'         => {fields => 'template_id'},
    'Krang::Template::NoDeleteAccess'       => {fields => ['template_id']},
    'Krang::Template::NoRestoreAccess'      => {fields => ['template_id']},
);
use Storable qw(nfreeze thaw);
use Time::Piece;
use Time::Piece::MySQL;

# Internal Module Depenedencies
################################
use Krang::ClassLoader 'Category';
use Krang::ClassLoader DB      => qw(dbh);
use Krang::ClassLoader Conf    => qw(SavedVersionsPerTemplate);
use Krang::ClassLoader History => qw(add_history);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'Site';
use Krang::ClassLoader Log => qw(debug);
use Krang::ClassLoader 'Publisher';
use Krang::ClassLoader 'UUID';

#
# Package Variables
####################
# Constants
############
# Read-only fields for the object
use constant TEMPLATE_RO => qw(template_id
  template_uuid
  checked_out
  checked_out_by
  creation_date
  deploy_date
  deployed
  deployed_version
  testing
  url
  version
  retired
  trashed
  read_only);

# Read-write fields
use constant TEMPLATE_RW => qw(category_id
  content
  filename);

# Fieldnames for template_version
use constant VERSION_COLS => qw(data
  template_id
  version);

# Globals
##########

# Lexicals
###########
my %template_args = map { $_ => 1 } TEMPLATE_RW;
my %template_cols = map { $_ => 1 } TEMPLATE_RO, TEMPLATE_RW;

# Interal Module Dependecies (con't)
####################################
# had to define constants before we could use them
use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get                              => [
    TEMPLATE_RO, qw( may_see
      may_edit )
  ],
  get_set => [grep { $_ ne 'filename' } TEMPLATE_RW];

sub id_meth   { 'template_id' }
sub uuid_meth { 'template_uuid' }

=head1 INTERFACE

=head2 FIELDS

This module employs Krang::MethodMaker to provide accessors for all and
mutators for some of the object's fields.  The fields can be accessed and set
in the following manner:

 # accessor
 $value = $template_obj->readable_field();

 # mutator
 $template->obj->readable_and_writeable_field( $value );

The four read/write fields for the object are:

=over 4

=item * category

A reference to the category object to which this template belongs.
Returns undef if template does not have a category (global templates
don't).

=cut

sub category {
    my $self = shift;
    return undef unless $self->{category_id};
    my ($cat) = pkg('Category')->find(category_id => $self->{category_id});
    return $cat;
}

=item * category_id

Integer that identifies the parent category of the template object.

=item * content

The HTML::Template code that make up the template.

=item * filename

The filename into which the 'content' will be output once the template is
deployed.

=cut

sub filename {
    my $self = shift;
    return $self->{filename} unless @_;
    my $filename = shift;

    # make sure it's kosher
    croak(__PACKAGE__ . "->init(): missing required filename parameter.")
      unless $filename;
    croak(__PACKAGE__ . "->init(): filename parameter '$filename' does not end in '.tmpl'.")
      unless $filename =~ /\.tmpl$/;
    croak(__PACKAGE__ . "->init(): filename parameter '$filename' contained invalid characters.")
      unless $filename =~ /^[-\w]+\.tmpl$/;

    return $self->{filename} = $filename;
}

=back

The remaining read-only fields are:

=over 4

=item * checked_out

Boolean that is true when the given object is checked_out.

=item * checked_out_by

Interger id of the user object that has the template object checked out which
corresponds to the id of an object in the user table.

=item * creation_date

Date stamp identifying when the object was created.  This is a
Time::Piece object, initalized during new() to the current date and
time.

=item * deployed

Boolean that is true when the given object has been deployed.

=item * deploy_date

Date stamp identifying when the object was last deployed.  This is a
Time::Piece object.

=item * deployed_version

Integer identifying the version of the template that is currently deployed.

=item * site

A reference to the Krang::Site object with which this object is associated.

=cut

sub site {
    my $self   = shift;
    my $cat_id = $self->{category_id};
    my ($cat) = pkg('Category')->find(category_id => $cat_id);
    return $cat->site();
}

=item * template_id

Integer id of the template object corresponding to its id in the template
table.

=item * testing

Boolean that is true when the object has been marked for testing, i.e. the
current object will be used to generate output for preview irrespective
of deployed versions of the template.

=item * url

Text field where the object's calculated virtual url is stored.  The url is
calculated by concatenating its category's 'url' and its 'filename'.  The
purpose of this field is to ensure the uniqueness of a template.

=item * version

Integer identifying the version of the template object in memory.

=back

=head2 METHODS

=over 4

=item $template = Krang::Template->new( %params )

Constructor provided by Krang::MethodMaker.  Accepts a hash its argument.
Validation of the keys in the hash is performed in the init() method.  The
valid keys to this hash are:

=over 4

=item * category

=item * category_id

=item * content

=item * filename

=back

The filename arguement is required.

=item $template = $template->checkin()

=item $template = Krang::Template->checkin( $template_id )

Class or instance method for checking in a template object, as a class method
a template id must be passed.

Will throw Krang::Template::NoEditAccess unless user has edit access.

If the call to verify_checkout() fails, a Checkout exception is thrown.

=cut

sub checkin {
    my $self = shift;
    my $id   = shift || $self->{template_id};
    my $dbh  = dbh();

    # get object if we don't have it
    ($self) = pkg('Template')->find(template_id => $id) unless ref $self;

    # Throw exception unless we have edit access
    Krang::Template::NoEditAccess->throw(
        message     => "Not allowed to check in this template",
        template_id => $id
    ) unless ($self->may_edit);

    # get admin permissions
    my %admin_perms = pkg('Group')->user_admin_permissions();

    # make sure we're checked out, unless we have may_checkin_all powers
    $self->verify_checkout() unless $admin_perms{may_checkin_all};

    my $query = <<SQL;
UPDATE template
SET checked_out = ?, checked_out_by = ?, testing = ?
WHERE template_id = ?
SQL

    $dbh->do($query, undef, 0, 0, 0, $id);

    # update checkout fields
    $self->{checked_out}    = 0;
    $self->{checked_out_by} = 0;
    $self->{testing}        = 0;
    add_history(object => $self, action => 'checkin',);

    return $self;
}

=item $template = $template->checkout()

=item $template = Krang::Template->checkout( $template_id )

Class or instance method for checking out template objects, as a class method
a template id must be passed.

Will throw Krang::Template::NoEditAccess unless user has edit access.

This method throws Krang::Template::Checkout if the object is already checked out by another user.

=cut

sub checkout {
    my $self    = shift;
    my $id      = shift || $self->{template_id};
    my $dbh     = dbh();
    my $user_id = $ENV{REMOTE_USER};

    # make sure we actually have an object
    ($self) = pkg('Template')->find(template_id => $id) unless ref $self;

    # Throw exception unless we have edit access
    Krang::Template::NoEditAccess->throw(
        message     => "Not allowed to check out this template",
        template_id => $id
    ) unless ($self->may_edit);

    # short circuit checkout, if possible
    if ($self->{checked_out}) {
        Krang::Template::Checkout->throw(
            message     => "Template checked out " . "by another user.",
            template_id => $id,
            user_id     => $self->{checked_out_by}
        ) if $self->{checked_out_by} != $user_id;
        return $self;
    }

    eval {

        # lock template table
        $dbh->do("LOCK TABLES template WRITE");
        my $query = <<SQL;
UPDATE template
SET checked_out = ?, checked_out_by = ?
WHERE template_id = ?
SQL

        $dbh->do($query, undef, (1, $user_id, $id));

        # unlock template table
        $dbh->do("UNLOCK TABLES");
    };

    if ($@) {
        my $eval_error = $@;

        # unlock the table, so it's not locked forever
        $dbh->do("UNLOCK TABLES");
        croak($eval_error);
    }

    # update checkout fields
    $self->{checked_out}    = 1;
    $self->{checked_out_by} = $user_id;
    add_history(object => $self, action => 'checkout',);

    return $self;
}

=item $template->delete()

=item Krang::Template->delete( $template_id )

Class or instance method for deleting template objects.  As a class method the
method accepts either a single template id or array object ids.

Deletion means deleting all instances of the object in the version table as
well as the current version in the template.

This method attempts to check out the template before deleting; checkout() will
croak if the object is checked out by another user.

Will throw Krang::Template::NoEditAccess unless user has edit access.

'1' is returned if the deletion was successful.

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->{template_id};

    # checkout the template
    ($self) = pkg('Template')->find(template_id => $id) unless ref $self;

    # Is user allowed to delete objects from the trashbin?
    Krang::Template::NoDeleteAccess->throw(
        message     => "Not allowed to delete templates",
        template_id => $self->template_id
    ) unless pkg('Group')->user_admin_permissions('admin_delete');

    # Check out first
    $self->checkout;

    # if the template has been deployed, undeploy it.
    if ($self->{deployed}) {
        my $publisher = pkg('Publisher')->new();
        $publisher->undeploy_template(template => $self);
    }

    # first delete history for this object
    pkg('History')->delete(object => $self);

    my $t_query = "DELETE FROM template WHERE template_id = ?";
    my $v_query = "DELETE FROM template_version WHERE template_id = ?";
    my $dbh     = dbh();
    $dbh->do($t_query, undef, ($id));
    $dbh->do($v_query, undef, ($id));

    # remove from trash
    pkg('Trash')->remove(object => $self);

    add_history(
        object => $self,
        action => 'delete',
    );

    return 1;
}

=item $template->deploy()

Convenience method to Krang::Publisher, deploys template.

=cut

sub deploy {
    my $self      = shift;
    my $publisher = pkg('Publisher')->new();

    $publisher->deploy_template(template => $self);
}

=item $template->duplicate_check()

This method checks whether the url of a template is unique.  A 
Krang::Template::DuplicateURL
exception is thrown if a duplicate is found, '0' is returned otherwise.

=cut

sub duplicate_check {
    my $self        = shift;
    my $id          = $self->{template_id} || 0;
    my $template_id = 0;

    my $query = <<SQL;
SELECT template_id
FROM   template
WHERE  url = '$self->{url}'
AND    retired = 0
AND    trashed  = 0
SQL
    $query .= "AND template_id != $id" if $id;
    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->bind_col(1, \$template_id);
    $sth->fetch();
    $sth->finish();

    Krang::Template::DuplicateURL->throw(
        message     => 'Duplicate URL',
        template_id => $template_id
    ) if $template_id;

    return $template_id;
}

=item $template = $template->mark_as_deployed()

Instance method designed to work with Krang::Publisher->deploy_template to deploy
templates.

The method updates the 'deployed', 'deploy_date', 'deployed_version', and
'testing' fields in the db.

=cut

sub mark_as_deployed {
    my ($self) = @_;

    my $dbh = dbh();
    my $id  = $self->{template_id};

    # get value of now() for DB.
    my $time        = localtime;
    my $deploy_date = $time->mysql_datetime;

    # update deploy fields
    my $query = <<SQL;
UPDATE template
SET deployed = ?, deploy_date = ?, deployed_version = ?, testing = ?
WHERE template_id = ?
SQL

    $dbh->do($query, undef, (1, $deploy_date, $self->{version}, 0, $id));

    add_history(object => $self, action => 'deploy',);

    # set internal flags as well.
    $self->{deployed}         = 1;
    $self->{deployed_version} = $self->{version};
    $self->{testing}          = 0;
    $self->{deploy_date}      = $time;

    return $self;
}

=item $template = $template->mark_as_undeployed()

Instance method designed to work with Krang::Publisher->undeploy_template to mark
templates that have been removed from the publish path.

The method updates the 'deployed', 'deploy_date', and 'deployed_version' fields in the db.

=cut

sub mark_as_undeployed {
    my ($self) = @_;

    my $dbh = dbh();
    my $id  = $self->{template_id};

    # update deploy fields
    my $query = <<SQL;
UPDATE template
SET deployed = 0, deploy_date = NULL, deployed_version = NULL
WHERE template_id = ?
SQL

    $dbh->do($query, undef, ($id));

    #    add_history(object => $self, action => 'undeploy',);

    # set internal flags as well.
    $self->{deployed}         = 0;
    $self->{deployed_version} = undef;
    $self->{deploy_date}      = undef;

    return $self;
}

=item @templates = Krang::Template->find( %params )

=item @template = Krang::Template->find( template_id => 1 )

=item @templates = Krang::Template->find( template_id => [1, 2, 3, 5, 8] )

=item @template_ids = Krang::Template->find( ids_only => 1, etc., )

=item $count = Krang::Template->find( count => 1, etc., )

Class method that returns the template objects or ids matching the criteria
provided in %params.

Fields may be matched using SQL matching.  Appending "_like" to a field name
will specify a case-insensitive SQL match.

@templates = Krang::Template->find(filename_like => '%' . $string . '%');

Notice that it is necessary to surround terms with '%' to perform sub-string
matches.

The list valid search fields is:

=over 4

=item * category_id

=item * below_category_id

=item * checked_out

=item * checked_out_by

=item * creation_date

=item * deploy_date

=item * deployed

=item * filename

=item * full_text_string

=item * template_id

=item * template_uuid

=item * testing

=item * version

=item * read_only

=item * simple_search

=item * simple_search_check_full_text (boolean)

=item * 

=back

Additional criteria which affect the search results are:

=over 4

=item * count

If this argument is specified, the method will return a count of the templates
matching the other search criteria provided.

=item * ids_only

Returns only template ids for the results found in the DB, not objects.

=item * limit

Specify this argument to determine the maximum amount of template object or
template ids to be returned.

=item * offset

Sets the offset from the first row of the results to return.

=item * order_by

Specify the field by means of which the results will be sorted.  By default
results are sorted with the 'template_id' field.

=item * order_desc

Set this flag to '1' to sort results relative to the 'order_by' field in
descending order, by default results sort in ascending order

=item * include_live

Include live templates in the search result. Live templates are
templates that are neither retired nor have been moved to the
trashbin. Set this option to 0, if find() should not return live
templates.  The default is 1.

=item * include_retired

Set this option to 1 if you want to include retired templates in the
search result. The default is 0.

=item  * include_trashed

Set this option to 1 if you want to include trashed templates in the
search result. Trashed templates live in the trashbin. The default is 0.

B<NOTE:>When searching for template_id, these three include_* flags are
not taken into account!

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
    my $descend = delete $args{descend} || '';
    my $limit   = delete $args{limit}   || '';
    my $offset  = delete $args{offset}  || '';
    my $order_by = "t." . (delete $args{order_by} || 'template_id');

    # set search includes
    my $include_retired = delete $args{include_retired} || 0;
    my $include_trashed = delete $args{include_trashed} || 0;
    my $include_live    = delete $args{include_live};
    $include_live = 1 unless defined($include_live);

    # set search fields
    my $count    = delete $args{count}    || '';
    my $ids_only = delete $args{ids_only} || '';

    # set bool to join with category table
    my $category = exists $args{below_category_id} ? 1 : 0;

    # set bool to determine whether to use $row or %row for binding below
    my $single_column = $ids_only || $count ? 1 : 0;

    # set bool to determine whether simple search should check full text
    my $simple_full_text = delete $args{simple_search_check_full_text} || 0;

    croak(  __PACKAGE__
          . "->find(): 'count' and 'ids_only' were supplied. "
          . "Only one can be present.")
      if ($count && $ids_only);

    $fields =
      $count
      ? 'count(DISTINCT t.template_id)'
      : ($ids_only ? 't.template_id' : join(", ", map { "t.$_" } (keys %template_cols)));

    # handle version loading
    return $self->_load_version($args{template_id}, $args{version})
      if $args{version};

    # set up WHERE clause and @params, croak unless the args are in
    # TEMPLATE_RO or TEMPLATE_RW
    my @invalid_cols = ();
    for my $arg (keys %args) {
        my $like = 1 if $arg =~ /_like$/;
        (my $lookup_field = $arg) =~ s/^(.+)_like$/$1/;

        push(@invalid_cols, $arg)
          unless (
            grep { $lookup_field eq $_ } (
                keys(%template_cols),
                qw( simple_search
                  below_category_id
                  may_see
                  may_edit
                  full_text_string )
            )
          );

        if (   $arg eq 'template_id'
            && (ref($args{$arg}) || "") eq 'ARRAY'
            && scalar(@{$args{$arg}}) > 0)
        {
            my $tmp = join(" OR ", map { "t.template_id = ?" } @{$args{$arg}});
            $where_clause .= " ($tmp)";
            push @params, @{$args{$arg}};
        } elsif ($arg eq 'category_id'
            && (ref($args{$arg}) || "") eq 'ARRAY'
            && scalar(@{$args{$arg}}) > 0)
        {
            my $tmp = join(" OR ",
                map { defined $_ ? "t.category_id = ?" : "t.category_id IS NULL" } @{$args{$arg}});
            $where_clause .= " ($tmp)";

            # only keep defined since we've taken care of NULL above
            my @values = grep { defined $_ } @{$args{$arg}}; 
            push @params, @values;
        } elsif ($arg eq 'below_category_id') {
            my ($cat) = pkg('Category')->find(category_id => $args{$arg});
            if ($cat) {
                $where_clause =
                    "c.category_id = ? AND "
                  . "t.url LIKE ?"
                  . ($where_clause ? " AND $where_clause" : '');
                unshift @params, $cat->url . "%";
                unshift @params, $args{$arg};
            }
        } elsif ($arg eq 'full_text_string') {
            foreach my $phrase ($self->_search_text_to_phrases($args{$arg})) {
                $where_clause .= ' AND ' if $where_clause;
                if ($phrase =~ /^\s(.*)\s$/) {

                    # user wants full-word match: replace spaces w/ MySQL word boundaries
                    $where_clause .= '(t.content RLIKE CONCAT( "[[:<:]]", ?, "[[:>:]]" ))';
                    push(@params, $1);
                } else {

                    # user wants regular substring match
                    $where_clause .= '(t.content LIKE ?)';
                    push(@params, "%${phrase}%");
                }
            }
        } elsif ($arg eq 'simple_search') {
            foreach my $phrase ($self->_search_text_to_phrases($args{$arg})) {
                my $numeric = ($phrase =~ /^\d+$/) ? 1 : 0;
                if (!$numeric) {
                    $phrase =~ s/_/\\_/g;    # escape any literal
                    $phrase =~ s/%/\\%/g;    # SQL wildcard chars
                }
                $where_clause .= " AND " if $where_clause;
                $where_clause .= '(' . ($numeric ? "t.template_id = ?" : "t.url LIKE ?");
                push @params, ($numeric ? $phrase : "%" . $phrase . "%");
                if ($simple_full_text) {
                    if ($phrase =~ /^\s(.*)\s$/) {

                        # user wants full-word match: replace spaces w/ MySQL word boundaries
                        $where_clause .= ' OR t.content RLIKE CONCAT( "[[:<:]]", ?, "[[:>:]]" )';
                        push(@params, $1);
                    } else {

                        # user wants regular substring match
                        $where_clause .= ' OR t.content LIKE ?';
                        push(@params, "%${phrase}%");
                    }
                }
                $where_clause .= ')';
            }
        } elsif (
            grep {
                $arg eq $_
            } qw(may_see may_edit)
          )
        {
            my $fqfield = "ucpc.$arg";

            # On may_see and may_edit, always return "global" templates -- templates w/o a category
            $where_clause .= " AND " if ($where_clause);
            if ($args{$arg}) {

                # If we're looking for true vals, accept 1 or NULL
                $where_clause .= "($fqfield=1 OR $fqfield IS NULL)";
            } else {

                # If we're looking for false vals, accept only 0
                $where_clause .= "$fqfield=0";
            }
        } else {
            my $and = defined $where_clause && $where_clause ne '' ? ' AND' : '';
            $lookup_field = "t." . $lookup_field;
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

    # Get user asset permissions -- overrides may_edit if false
    my $template_access = pkg('Group')->user_asset_permissions('template');

    my $dbh = dbh();

    # Add may_see and may_edit fields
    unless ($count) {
        my @may_fields = ();
        push(@may_fields, "ucpc.may_see as may_see");
        if ($template_access eq "edit") {
            push(@may_fields, "ucpc.may_edit as may_edit");
        } else {
            push(@may_fields, $dbh->quote("0") . " as may_edit");
        }
        $fields .= ", " . join(", ", @may_fields);
    }

    # include live/retired/trashed
    unless ($args{template_id} or $args{template_uuid}) {
        if ($include_live) {
            unless ($include_retired) {
                $where_clause .= ' and ' if $where_clause;
                $where_clause .= ' t.retired = 0';
            }
            unless ($include_trashed) {
                $where_clause .= ' and ' if $where_clause;
                $where_clause .= ' t.trashed  = 0';
            }
        } else {
            if ($include_retired) {
                if ($include_trashed) {
                    $where_clause .= ' and ' if $where_clause;
                    $where_clause .= ' t.retired = 1 AND t.trashed = 1';
                } else {
                    $where_clause .= ' and ' if $where_clause;
                    $where_clause .= ' t.retired = 1 AND t.trashed = 0';
                }
            } else {
                if ($include_trashed) {
                    $where_clause .= ' and ' if $where_clause;
                    $where_clause .= ' t.trashed = 1';
                }
            }
        }
    }

    # construct base query
    my $query = qq( SELECT $fields FROM template t 
                    left join user_category_permission_cache as ucpc
                    ON ucpc.category_id = t.category_id
                    );
    $query .= ", category c" if $category;

    # Add user_id
    $where_clause .= " AND " if ($where_clause);
    $where_clause .= "(ucpc.user_id=? OR t.category_id IS NULL)";
    my $user_id = $ENV{REMOTE_USER};
    push(@params, $user_id);

    # add WHERE and ORDER BY clauses, if any
    $query .= " WHERE $where_clause" if $where_clause;
    $query .= " GROUP BY t.template_id" unless ($count);
    $query .= " ORDER BY $order_by $ascend" if $order_by;

    # add LIMIT clause, if any
    if ($limit) {
        $query .= $offset ? " LIMIT $offset, $limit" : " LIMIT $limit";
    } elsif ($offset) {
        $query .= " LIMIT $offset, 18446744073709551615";
    }

    debug(__PACKAGE__ . "->find: Executing query $query with params: @params");

    my $sth = $dbh->prepare($query);
    $sth->execute(@params);

    # holders for query results and new objects
    my ($row, @templates);

    # bind fetch calls to $row or %$row
    # a possibly insane micro-optimization :)
    if ($single_column) {
        $sth->bind_col(1, \$row);
    } else {
        $sth->bind_columns(\(@$row{@{$sth->{NAME_lc}}}));
    }

    # construct template objects from results
    while ($sth->fetchrow_arrayref()) {

        # if we just want count or ids
        if ($single_column) {
            push @templates, $row;
        } else {

            # Handle permissions for global templates -- set to asset permissions
            unless (defined($row->{category_id})) {
                $row->{may_edit} = 1 if ($template_access eq "edit");
                $row->{may_see} = 1;
            }

            push @templates, bless({%$row}, $self);
            foreach my $date_field (grep { /_date$/ } keys %{$templates[-1]}) {
                my $val = $templates[-1]->{$date_field};
                if (defined $val and $val ne '0000-00-00 00:00:00') {
                    $templates[-1]->{$date_field} = Time::Piece->from_mysql_datetime($val);
                } else {
                    $templates[-1]->{$date_field} = undef;
                }
            }
        }
    }

    # return number of rows if count, otherwise an array of template ids or
    # objects
    return $count ? $templates[0] : @templates;
}

# this private helper method takes a search string and returns
# an array of phrases - e.g. ONE TWO THREE returns (ONE, TWO,
# THREE) whereas "ONE TWO" THREE returns (ONE TWO, THREE)
sub _search_text_to_phrases {
    my ($self, $text) = @_;
    my @phrases;

    # first add any quoted text as multi-word phrase(s)
    while ($text =~ s/([\'\"])([^\1]*?)\1//) {
        my $phrase = $2;
        $phrase =~ s/\s+/ /;
        push @phrases, $phrase;
    }

    # then split remaining text into one-word phrases
    push @phrases, (split /\s+/, $text);
    return @phrases;
}

# handles version loading for find()
sub _load_version {
    my ($self, $id, $version) = @_;
    my $dbh   = dbh();
    my $query = <<SQL;
SELECT data FROM template_version
WHERE template_id = ? AND version = ?
SQL
    my ($row) = $dbh->selectrow_array($query, undef, $id, $version);

    my @result;
    eval { @result = (thaw($row)) };
    croak("Unable to thaw version '$version' for id '$id': $@") if $@;

    return @result;
}

# Validates the input from new(), and croaks if an arg isn't in %template_args
sub init {
    my $self = shift;
    my %args = @_;
    my @bad_args;

    for (keys %args) {
        push @bad_args, $_
          unless exists $template_args{$_} || $_ eq 'category';
    }

    # croak if we've been given invalid args
    croak(
        __PACKAGE__ . "->init(): The following invalid arguments were " . "supplied - " . join ' ',
        @bad_args
    ) if @bad_args;

    # if we have a category are use it to set 'category_id'
    my $category = delete $args{category} || '';

    if ($category) {

        # make sure it's a category object before attempting to set
        croak(__PACKAGE__ . "->init(): 'category' argument must be a 'Krang::Category' object.")
          unless (ref($category) and $category->isa('Krang::Category'));
        $self->{category_id} = $category->category_id;
    }

    # setup defaults
    $self->{version}        = 0;
    $self->{checked_out}    = 1;
    $self->{checked_out_by} = $ENV{REMOTE_USER};
    $self->{deployed}       = 0;
    $self->{testing}        = 0;
    $self->{creation_date}  = localtime();
    $self->{template_uuid}  = pkg('UUID')->new();
    $self->{retired}        = 0;
    $self->{trashed}        = 0;
    $self->{read_only}      = 0;

    $self->hash_init(%args);

    # Set up permissions
    $self->{may_see}  = 1;
    $self->{may_edit} = 1;

    return $self;
}

=item $template = $template->mark_for_testing()

This method sets the testing fields in the template table to allow for the
testing of output of an undeployed template.  If the method call is successful,
the 'testing' field is updated in the db.  'checked_out_by' will identify the user
that has flagged the template for testing.

The method croaks if the template is not checked out or checked out by another
user.

=cut

sub mark_for_testing {
    my $self = shift;
    $self->verify_checkout();

    my $query = <<SQL;
UPDATE template
SET testing = ?
WHERE template_id = ?
SQL

    my $dbh = dbh();
    $dbh->do($query, undef, (1, $self->{template_id}));

    # update testing field in memory
    $self->{testing} = 1;

    return $self;
}

=item $template = $template->mark_for_testing()

This method unsets the testing fields in the template table.

The method croaks if the template is not checked out or checked out by another
user.

=cut

sub unmark_for_testing {
    my $self = shift;
    $self->verify_checkout();

    my $query = <<SQL;
UPDATE template
SET testing = ?
WHERE template_id = ?
SQL

    my $dbh = dbh();
    $dbh->do($query, undef, (0, $self->{template_id}));

    # update testing field in memory
    $self->{testing} = 0;

    return $self;
}

=item C<< $all_version_numbers = $template->all_versions(); >>

Returns an arrayref containing all the existing version numbers for this template object.

=cut

sub all_versions {
    my $self = shift;
    my $dbh  = dbh;
    return $dbh->selectcol_arrayref('SELECT version FROM template_version WHERE template_id=?',
        undef, $self->template_id);
}

=item C<< $template->prune_versions(number_to_keep => 10); >>

Deletes old versions of this template object. By default prune_versions() keeps
the number of versions specified by SavedVersionsPerTemplate in krang.conf;
this can be overridden as above. In either case, it returns the number of 
versions actually deleted.

=cut

sub prune_versions {
    my ($self, %args) = @_;
    my $dbh = dbh;

    # figure out how many versions to keep
    my $number_to_keep = $args{number_to_keep} || SavedVersionsPerTemplate;
    return 0 unless $number_to_keep;

    # figure out how many versions can be deleted
    my @all_versions     = @{$self->all_versions};
    my $number_to_delete = @all_versions - $number_to_keep;
    return 0 unless $number_to_delete > 0;

    # delete the oldest ones (which will be first since the list is ascending)
    my @versions_to_delete = splice(@all_versions, 0, $number_to_delete);
    $dbh->do(
        'DELETE FROM template_version WHERE template_id = ? AND version IN ('
          . join(',', ("?") x @versions_to_delete) . ')',
        undef, $self->template_id, @versions_to_delete
    ) unless $args{test_mode};
    return $number_to_delete;
}

=item $template->revert( $version )

Reverts template object data to that of a previous version.

Reverting to a previous version effectively means deserializing the previous
version from the database and using it to create a new, identical version, 
overwriting the values currently in the object. 

The method croaks if the template is not checked out, checked out by another
user, or it can't deserialize the retrieved version.

Otherwise, if the new version is successfully written to disk (no duplicate
URL errors, etc.), the object itself is returned; if not, an error is returned.

=cut

sub revert {
    my ($self, $version) = @_;
    my $dbh = dbh();
    my $id  = $self->template_id();

    $self->verify_checkout();

    my $query = <<SQL;
SELECT data
FROM template_version
WHERE template_id = ? AND version = ?
SQL

    my @row = $dbh->selectrow_array($query, undef, ($id, $version));

    # preserve version and checkout status
    my %preserve = (
        version          => $self->{version},
        deployed_version => $self->{deployed_version},
        checked_out_by   => $self->{checked_out_by},
        checked_out      => $self->{checked_out}
    );

    # get old version
    my $obj;
    eval { $obj = thaw($row[0]) };

    # catch Storable exception
    croak(__PACKAGE__ . "->revert(): Unable to deserialize object for " . "template id '$id' - $@")
      if $@;

    # copy old data into current object, perserving what is meant to
    # be preserved.
    %{$self} = (%$obj, %preserve);

    # attempt disk-write
    eval { $self->save };
    return $@ if $@;

    add_history(object => $self, action => 'revert',);

    return $self;
}

=item $template = $template->save()

Saves template data in memory to the database.

Stores a copy of the objects current contents to the template table. The
version field is incremented on each save unless called with 'keep_version'
 set to 1.

duplicate_check() throws an exception if the template's url isn't unique.
verify_checkout() throws an exception if the template isn't checked out or if
it's checked out to another user. The method croaks if its executed SQL affects
no rows in the DB.

Will throw Krang::Template::NoEditAccess unless user has edit access.

Will throw Krang::Template::NoCategoryEditAccess unless user has edit access
to the specified category.


=cut

sub save {
    my ($self, %args) = @_;
    my $user_id = $ENV{REMOTE_USER};
    my $id = $self->{template_id} || 0;

    # list of DB fields to insert or update; exclude 'template_id'
    my @save_fields = grep { $_ ne 'template_id' } keys %template_cols;

    # Throw exception unless we have edit access
    Krang::Template::NoEditAccess->throw(
        message     => "Not allowed to save this template",
        template_id => $self->template_id
    ) unless ($self->may_edit);

    # calculate url
    my $url = "";
    if ($self->{category_id}) {
        my ($cat) = pkg('Category')->find(category_id => $self->{category_id});

        # Throw exception unless we have edit access
        Krang::Template::NoCategoryEditAccess->throw(
            message     => "Not allowed to save template in this category",
            category_id => $self->{category_id}
        ) unless ($cat->may_edit);

        $url = $cat->url;
    }

    $self->{url} = _build_url($url, $self->{filename});

    # check for duplicate url
    $self->duplicate_check();

    # make sure we've checked out the object
    $self->verify_checkout() if $id;

    # increment version number
    $self->{version} = $self->{version} + 1 unless $args{keep_version};

    # set up query
    my ($query, @tmpl_params);
    if ($id) {
        $query =
            "UPDATE template SET "
          . join(', ', map { " $_=? " } @save_fields)
          . "WHERE template_id = ?";
    } else {
        $query =
            "INSERT INTO template ("
          . join(",", @save_fields)
          . ") VALUES ("
          . join(",", (("?") x @save_fields)) . ")";
    }

    # construct array of bind_parameters
    foreach my $field (@save_fields) {
        if ($field =~ /_date$/) {
            push(@tmpl_params, defined $self->{$field} ? $self->{$field}->mysql_datetime : undef);
        } else {
            push(@tmpl_params, $self->{$field});
        }
    }
    push @tmpl_params, $id if $id;

    # get database handle
    my $dbh = dbh();

    debug(__PACKAGE__ . "::save() SQL: " . $query);
    debug(  __PACKAGE__
          . "::save() SQL ARGS: "
          . join(',', map { defined $_ ? $_ : 'undef' } @tmpl_params));

    # do the save
    $dbh->do($query, undef, @tmpl_params);

    # get template_id for new objects
    $self->{template_id} = $dbh->{mysql_insertid} unless $id;

    # save a copy in the version table
    my $frozen;
    eval { $frozen = nfreeze($self) };

    # catch any exception thrown by Storable
    croak(  __PACKAGE__
          . "->prepare_for_edit(): Unable to serialize object "
          . "template id '$id' - $@")
      if $@;

    # do the insert
    $dbh->do("REPLACE INTO template_version (data, template_id, version) " . "VALUES (?,?,?)",
        undef, $frozen, $self->{template_id}, $self->{version});

    # prune previous versions from the version table
    $self->prune_versions();

    add_history(object => $self, action => 'new') if $self->{version} == 1;
    add_history(object => $self, action => 'save',);

    return $self;
}

=item $template = $template->update_url( $url );

Method called on object to propagate changes to parent category's 'url'.

=cut

sub update_url {
    my ($self, $url) = @_;
    $self->{url} = _build_url($url, $self->{filename});
    return $self;
}

=item $template->serialize_xml(writer => $writer, set => $set)

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self,   %args) = @_;
    my ($writer, $set)  = @args{qw(writer set)};
    local $_;

    # open up <template> linked to schema/template.xsd
    $writer->startTag(
        'template',
        "xmlns:xsi"                     => "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation" => 'template.xsd'
    );

    $writer->dataElement(template_id   => $self->{template_id});
    $writer->dataElement(template_uuid => $self->{template_uuid});
    $writer->dataElement(filename      => $self->{filename});
    $writer->dataElement(url           => $self->{url});
    $writer->dataElement(category_id   => $self->{category_id})
      if $self->{category_id};
    $writer->dataElement(content       => $self->{content});
    $writer->dataElement(creation_date => $self->{creation_date}->datetime);
    $writer->dataElement(deploy_date   => $self->{deploy_date}->datetime) if $self->{deploy_date};
    $writer->dataElement(version       => $self->{version});
    $writer->dataElement(deployed_version => $self->{deployed_version})
      if $self->{deployed_version};
    $writer->dataElement(retired   => $self->retired);
    $writer->dataElement(trashed   => $self->trashed);
    $writer->dataElement(read_only => $self->read_only);

    # add category to set
    $set->add(object => $self->category, from => $self)
      if $self->{category_id};

    # all done
    $writer->endTag('template');
}

=item C<< $template = Krang::Template->deserialize_xml(xml => $xml, set => $set, no_update => 0) >>

Deserialize XML.  See Krang::DataSet for details.

If an incoming template has the same URL as an existing template then an
update will occur, unless no_update is set.

Note that the creation_date, version, deploy_date, deployed_version
fields are ignored when importing templates.

Also, all templates are deployed after deserialization.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($xml, $set, $no_update) = @args{qw(xml set no_update)};

    # divide FIELDS into simple and complex groups
    my (%complex, %simple);

    # strip out all fields we don't want updated or used.
    @complex{
        qw(template_id deploy_date creation_date url
          checked_out checked_out_by version deployed testing
          deployed_version category_id template_uuid trashed retired read_only)
      }
      = ();
    %simple = map { ($_, 1) } grep { not exists $complex{$_} } (TEMPLATE_RO, TEMPLATE_RW);

    # parse it up
    my $data = pkg('XML')->simple(
        xml           => $xml,
        suppressempty => 1
    );

    # is there an existing object?
    my $template;

    # start with UUID lookup
    if (not $args{no_uuid} and $data->{template_uuid}) {
        ($template) = $pkg->find(template_uuid => $data->{template_uuid});

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A template object with the UUID '$data->{template_uuid}' already"
              . " exists and no_update is set.")
          if $template and $no_update;
    }

    # proceed to URL lookup if no dice
    unless ($template or $args{uuid_only}) {
        ($template) = pkg('Template')->find(url => $data->{url});

        # if not updating this is fatal
        Krang::DataSet::DeserializationFailed->throw(
            message => "A template object with the url '$data->{url}' already "
              . "exists and no_update is set.")
          if $template and $no_update;
    }

    if ($template) {
        debug(__PACKAGE__ . "->deserialize_xml : found template");

        $template->checkout;

        # update simple fields
        $template->{$_} = $data->{$_} for keys %simple;

        # update the category, which can change now with UUID matching
        if ($data->{category_id}) {
            my $category_id = $set->map_id(
                class => pkg('Category'),
                id    => $data->{category_id}
            );
            $template->category_id($category_id);
        }

    } else {

        # create a new template object with category and simple fields
        if ($data->{category_id}) {
            $template = pkg('Template')->new(
                category_id => $set->map_id(
                    class => pkg('Category'),
                    id    => $data->{category_id}
                ),
                (map { ($_, $data->{$_}) } keys %simple)
            );
        } else {
            $template = pkg('Template')->new((map { ($_, $data->{$_}) } keys %simple));
        }
    }

    $template->save();
    $template->checkin;

    my $publisher = pkg('Publisher')->new();

    # only deploy if the previous template was deployed
    $publisher->deploy_template(template => $template)
      if ($data->{deployed_version});

    return $template;
}

=item $template->verify_checkout()

Instance method that verifies the given object is both checked out and checked
out to the current user.

A Krang::Template::Checkout exception is thrown if the template isn't checked
out or is checked out by another user, otherwise, '1' is returned.

=cut

sub verify_checkout {
    my $self    = shift;
    my $id      = $self->{template_id};
    my $user_id = $ENV{REMOTE_USER};

    Krang::Template::Checkout->throw(
        message     => "Template isn't checked out.",
        template_id => $id
    ) unless $self->{checked_out};

    my $cob = $self->{checked_out_by};

    Krang::Template::Checkout->throw(
        message     => "Template checked out by " . "another user.",
        template_id => $id,
        user_id     => $cob
    ) unless $cob == $user_id;

    return 1;
}

sub _build_url { (my $url = join('/', @_)) =~ s|/+|/|g; return $url; }

=item C<< $template->retire() >>

=item C<< Krang::Template->retire(template_id => $template_id) >>

Archive the template, i.e. undeploy it and don't show it on the Find
Template screen.  Throws a Krang::Template::NoEditAccess exception if
user may not edit this template. Croaks if the template is checked out
by another user.

=cut

sub retire {
    my ($self, %args) = @_;
    unless (ref $self) {
        my $template_id = $args{template_id};
        ($self) = pkg('Template')->find(template_id => $template_id);
        croak("Unable to load template '$template_id'.") unless $self;
    }

    # Is user allowed to otherwise edit this object?
    Krang::Template::NoEditAccess->throw(
        message     => "Not allowed to edit template",
        template_id => $self->template_id
    ) unless ($self->may_edit);

    # make sure we are the one
    $self->checkout;

    # undeploy
    pkg('Publisher')->new->undeploy_template(template => $self);

    # retire the template
    my $dbh = dbh();
    $dbh->do(
        "UPDATE template
              SET    retired = 1
              WHERE  template_id = ?", undef,
        $self->{template_id}
    );

    # living in retire
    $self->{retired} = 1;

    $self->checkin();

    add_history(
        object => $self,
        action => 'retire'
    );
}

=item C<< $template->unretire() >>

=item C<< Krang::Template->unretire(template_id => $template_id) >>

Unretire the template, i.e. show it again on the Find Template
screen, but don't redeploy it. Throws a Krang::Template::NoEditAccess
exception if user may not edit this template. Throws a
Krang::Template::DuplicateURL exception if a template with the same
URL has been created in Live. Croaks if the template is checked out by
another user.

=cut

sub unretire {
    my ($self, %args) = @_;
    unless (ref $self) {
        my $template_id = $args{template_id};
        ($self) = pkg('Template')->find(template_id => $template_id);
        croak("Unable to load template '$template_id'.") unless $self;
    }

    # Is user allowed to otherwise edit this object?
    Krang::Template::NoEditAccess->throw(
        message     => "Not allowed to edit template",
        template_id => $self->template_id
    ) unless ($self->may_edit);

    # make sure no other template occupies our initial place (URL)
    $self->duplicate_check();

    # make sure we are the one
    $self->checkout;

    # alive again
    $self->{retired} = 0;

    # unretire the template
    my $dbh = dbh();
    $dbh->do(
        'UPDATE template
              SET    retired = 0
              WHERE  template_id = ?', undef,
        $self->{template_id}
    );

    add_history(
        object => $self,
        action => 'unretire',
    );

    # check it back in
    $self->checkin();
}

=item C<< $template->trash() >>

=item C<< Krang::Template->trash(template_id => $template_id) >>

Move the template to the trashbin, i.e. undeploy it and don't show it
on the Find Template screen.  Throws a Krang::Template::NoEditAccess
exception if user may not edit this template. Croaks if the template
is checked out by another user.

=cut

sub trash {
    my ($self, %args) = @_;
    unless (ref $self) {
        my $template_id = $args{template_id};
        ($self) = pkg('Template')->find(template_id => $template_id);
        croak("Unable to load template '$template_id'.") unless $self;
    }

    # Is user allowed to otherwise edit this object?
    Krang::Template::NoEditAccess->throw(
        message     => "Not allowed to edit template",
        template_id => $self->template_id
    ) unless ($self->may_edit);

    # make sure we are the one
    $self->checkout;

    # undeploy
    pkg('Publisher')->new->undeploy_template(template => $self);

    # store in trash
    pkg('Trash')->store(object => $self);

    # update object
    $self->{trashed} = 1;

    # release it
    $self->checkin();

    # and log it
    add_history(object => $self, action => 'trash');
}

=item C<< $template->untrash() >>

=item C<< Krang::Template->untrash(template_id => $template_id) >>

Restore the template from the trashbin, i.e. show it again on the Find
Template or Archived Templates screens (depending on the location from
where it was deleted).  Throws a Krang::Template::NoRestoreAccess
exception if user may not edit this template. Croaks if the template
is checked out by another user. This method is called by
Krang::Trash->restore().

=cut

sub untrash {
    my ($self, %args) = @_;
    unless (ref $self) {
        my $template_id = $args{template_id};
        ($self) = pkg('Template')->find(template_id => $template_id);
        croak("Unable to load template '$template_id'.") unless $self;
    }

    # Is user allowed to otherwise edit this object?
    Krang::Template::NoRestoreAccess->throw(
        message     => "Not allowed to restore template",
        template_id => $self->template_id
    ) unless ($self->may_edit);

    # make sure no other template occupies our initial place (URL)
    $self->duplicate_check unless $self->retired;

    # make sure we are the one
    $self->checkout;

    # unset trash flag in template table
    my $dbh = dbh();
    $dbh->do(
        'UPDATE template
              SET trashed = ?
              WHERE template_id = ?', undef,
        0,                            $self->{template_id}
    );

    # remove from trash
    pkg('Trash')->remove(object => $self);

    # maybe in retire, maybe alive again
    $self->{trashed} = 0;

    # check back in
    $self->checkin();

    add_history(
        object => $self,
        action => 'untrash',
    );
}

=item C<< $template->clone(category_id => $category_id) >>

Copy $template to the category having the specified category_id.  Returns
an unsaved and checked out copy.

=back

=cut

sub clone {
    my ($self, %args) = @_;

    croak("No Category ID specified where to copy to template to")
      unless $args{category_id};

    my $copy = bless({%$self} => ref($self));

    # redefine
    $copy->{template_id}      = undef;
    $copy->{template_uuid}    = pkg('UUID')->new;
    $copy->{category_id}      = $args{category_id};
    $copy->{version}          = 0;
    $copy->{testing}          = 0;
    $copy->{creation_date}    = localtime();
    $copy->{deploy_date}      = undef;
    $copy->{deployed}         = 0;
    $copy->{deployed_version} = 0;
    $copy->{retired}          = 0;
    $copy->{trashed}          = 0;
    $copy->{url}              = '';                   # is set by save()
    $copy->{checked_out}      = 1;
    $copy->{checked_out_by}   = $ENV{REMOTE_USER};

    return $copy;
}

=head1 TO DO

 * Prevent duplicate template objects and paths once pkg('Category') is
   completed

=head1 SEE ALSO

L<Krang>, L<Krang::DB>, L<Krang::Log>

=cut

my $Fire_and_Ice = <<END;

Some say the world will end in fire,
Some say in ice.
From what I've tasted of desire
I hold with those who favor fire.
But if it had to perish twice,
I think I know enough of hate
To know that for destruction ice
Is also great
And would suffice.

- Robert Frost

END

