package Krang::Template;

=head1 NAME

  Krang::Template - Interface for managing template objects.

=head1 SYNOPSIS

 my $template = Krang::Template->new(category_id => 1,
				     content => '<tmpl_var test>',
				     element_class_name => 'class_name');

 # save contents of the object to the DB.
 $template->save();

 # put the object back into circulation for other users
 $template->checkin();

 # checkout object to work on it
 $template->checkout();

 # save version of object to version table in preparation for edits
 $template->prepare_for_edit();

 # saves to the db again, increments version field of the object
 $template->save();

 # use this template for testing, will override deployed versions of the
 # same template
 $template->mark_for_testing();

 # deploy template, will output template to '$dir/$template->filename()',
 # unsets testing flag in the database
 $template->deploy_to( $dir );

 # reverts to template revision specified by $version
 $template->revert( $version );

 # remove all references to the object in the template and
 # template_version tables
 $template->delete();

 # returns array of template objects matching criteria in %params
 my @templates = Krang::Template->find( %params );

=head1 DESCRIPTION

Templates determine the form of this system's output.  This module provides a
means to check in, check out, edit, revert, save, and search Template objects.

A template is either associated with an element class and hence determines
its formatting or it may serve as some manner of miscellaneous utility
whether formatting or otherwise.  Template data, i.e. the 'content' field, is,
at present, intended to be in HTML::Template format.  All template filenames
will end in the extension '.tmpl'.  Users have the ability to revert to any
previous version of a template.  Past revisions of templates are maintained in
a template versioning table.  The current version of a template is stored in
the template table.

This module interfaces or will interface with Krang::CGI::Template,
Krang::Burner, the FTP interface, and the SOAP interface.

=cut

# Pragmas
##########
use strict;
use warnings;

# External Module Dependencies
###############################
use Carp qw(verbose croak);
use Storable qw(freeze thaw);
use Time::Piece::MySQL;

# Internal Module Depenedencies
################################
use Krang::Category;
use Krang::DB qw(dbh);
use Krang::Session qw(%session);
use Krang::History qw( add_history );

#
# Package Variables
####################
# Constants
############
# Read-only fields for the object
use constant TEMPLATE_RO => qw(template_id
			       checked_out
			       checked_out_by
			       creation_date
			       deploy_date
			       deployed
			       deployed_version
			       testing
			       url
			       version);

# Read-write fields
use constant TEMPLATE_RW => qw(category_id
			       content
			       element_class_name
			       filename);

# Fieldnames for template_version
use constant VERSION_COLS => qw(data
				template_id
				version);

# Globals
##########

# Lexicals
###########
my %template_args = map {$_ => 1} TEMPLATE_RW;
my %template_cols = map {$_ => 1} TEMPLATE_RO, TEMPLATE_RW;


# Interal Module Dependecies (con't)
####################################
# had to define constants before we could use them
use Krang::MethodMaker 	new_with_init => 'new',
  			new_hash_init => 'hash_init',
  			get => [TEMPLATE_RO],
  			get_set => [TEMPLATE_RW];


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

=item * category_id

Integer that identifies the parent category of the template object.

=item * content

The HTML::Template code that make up the template.

=item * element_class_name

The element with which the object is associated and hence for which it
generates output.

=item * filename

The filename into which the 'content' will be output once the template is
deployed.

=back

The remaining read-only fields are:

=over 4

=item * checked_out

Boolean that is true when the given object is checked_out.

=item * checked_out_by

Interger id of the user object that has the template object checked out which
corresponds to the id of an object in the user table.

=item * creation_date

Date stamp identifying when the object was created.

=item * deployed

Boolean that is true when the given object has been deployed.

=item * deploy_date

Date stamp identifying when the object was last deployed.

=item * deployed_version

Integer identifying the version of the template that is currently deployed.

=item * template_id

Integer id of the template object corresponding to its id in the template
table.

=item * testing

Boolean that is true when the object has been marked for testing, i.e. the
current object will be used to generate output for preview irrespective
of deployed versions of the template.

=item * url

Text field where the object's calculate virtual url is stored.  The url is
calculated by concatenating its category's 'url' and its 'filename'.  The
purpose of this field is to ensure the uniqueness of a template.

=item * version

Integer identifying the version of the template object in memory, which implies
the existence of n - 1 versions of the object in the template_version table

=back

=head2 METHODS

=over 4

=item $template = Krang::Template->new( %params )

Constructor provided by Krang::MethodMaker.  Accepts a hash its argument.
Validation of the keys in the hash is performed in the init() method.  The
valid keys to this hash are:

=over 4

=item * category_id

=item * content

=item * element_class_name

=item * filename

=back

Either of the args 'element_class_name' or 'filename' must be supplied.

=item $template = $template->checkin()

=item $template = Krang::Template->checkin( $template_id )

Class or instance method for checking in a template object, as a class method
a template id must be passed.

This method croaks if the object is checked out by another user; it does
nothing if the object is not checked out.

=cut

sub checkin {
    my $self = shift;
    my $id = shift || $self->{template_id};
    my $dbh = dbh();
    my $user_id = $session{user_id};
    my $query;

    if ($self->isa('Krang::Template')) {
        $self->verify_checkout();
    } else {
        $query = <<SQL;
SELECT checked_out, checked_out_by
FROM template
WHERE template_id = ?
SQL

        my ($co, $uid) = $dbh->selectrow_arrayref($query, undef, ($id));

        croak(__PACKAGE__ . "->checkin(): Template id '$_' is checked " .
              "out by the user '$uid'.")
          if ($co && defined $uid && $uid != $user_id);

    }

    $query = <<SQL;
UPDATE template
SET checked_out = ?, checked_out_by = ?
WHERE template_id = ?
SQL

    $dbh->do($query, undef, (0, 0, $id));

    # update checkout fields if this is an instance method call
    if ($self->isa('Krang::Template')) {
        $self->{checked_out} = 0;
        $self->{checked_out_by} = 0;
    }

    if ($self->isa('Krang::Template')) {
        add_history(    object => $self,
                        action => 'checkin',
               );
    } else {
        add_history(    object => ((Krang::Template->find(template_id => $id))[0]),
                        action => 'checkin',
               );
    }

    return $self;
}


=item $template = $template->checkout()

=item $template = Krang::Template->checkout( $template_id )

Class or instance method for checking out template objects, as a class method
a template id must be passed.

This method croaks if the object is already checked out by another user.

=cut

sub checkout {
    my $self = shift;
    my $id = shift || $self->{template_id};
    my $dbh = dbh();
    my $user_id = $session{user_id};
    my $instance_meth = 0;

    # short circuit checkout on instance method version of call...
    if ($self->isa('Krang::Template')) {
        $instance_meth = 1;
        return $self if ($self->{checked_out} &&
                         ($self->{checked_out_by} == $user_id));
    }

    eval {
        # lock template table
        $dbh->do("LOCK TABLES template WRITE");

        my $query = <<SQL;
SELECT checked_out, checked_out_by
FROM template
WHERE template_id = ?
SQL

        my ($co, $uid) = $dbh->selectrow_array($query, undef, ($id));

        croak(__PACKAGE__ . "->checkout(): Template id '$id' is " .
              "already checked out by user '$uid'")
          if ($co && $uid != $user_id);

        $query = <<SQL;
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

    # update checkout fields if this is an instance method call
    if ($instance_meth) {
        $self->{checked_out} = 1;
        $self->{checked_out_by} = $user_id;
    }

    if ($self->isa('Krang::Template')) {
        add_history(    object => $self,
                        action => 'checkout',
               );
    } else {
        add_history(    object => ((Krang::Template->find(template_id => $id))[0]),
                        action => 'checkout',
               );
    }

    return $self;
}


=item $true = $template->delete()

=item $true = Krang::Template->delete( $template_id )

Class or instance method for deleting template objects.  As a class method the
method accepts either a single template id or array object ids.

Deletion means deleting all instances of the object in the version table as
well as the current version in the template.

This method attempts to check out the template before deleting; checkout() will
croak if the object is checked out by another user.

Returns '1' on success.

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->{template_id};

    # checkout the template
    if ($self->isa('Krang::Template')) {
        $self->checkout();
    } else {
        $self = Krang::Template->checkout($id);
    }

    # first delete history for this object
    if ($self->{template_id}) {
        Krang::History->delete(object => $self);
    } else {
        Krang::History->delete( object => ((Krang::Template->find(template_id => $id))[0]) );
    }


    my $t_query = "DELETE FROM template WHERE template_id = ?";
    my $v_query = "DELETE FROM template_version WHERE template_id = ?";
    my $dbh = dbh();
    $dbh->do($t_query, undef, ($id));
    $dbh->do($v_query, undef, ($id));

    return 1;
}


=item $template_id = $template->duplicate_check()

This method checks whether the url of a template is unique.

=cut

sub duplicate_check {
    my $self = shift;
    my $id = $self->{template_id} || 0;
    my $template_id = 0;

    my $query = <<SQL;
SELECT template_id
FROM template
WHERE url = '$self->{url}'
SQL
    $query .= "AND template_id != $id" if $id;
    my $dbh = dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->bind_col(1, \$template_id);
    $sth->fetch();
    $sth->finish();

    return $template_id;
}


=item $template = $template->deploy_to( $dir_path )

Instance method designed to work with Krang::Burner->deploy() to deploy
templates.  The data in the 'content' field is written to $self->filename() in
the '$dir_path' directory.

The method updates the 'deployed', 'deploy_date', 'deployed_version', and
'testing' fields in the db.

An error is thrown if the method cannot write to the specified path.

=cut

sub deploy_to {
    my ($self, $dir_path) = @_;
    my $dbh = dbh();
    my $path = File::Spec->catfile($dir_path, $self->{filename});
    my $id = $self->{template_id};

    # write out file
    my $fh = IO::File->new(">$path") or
      croak(__PACKAGE__ . "->deploy_to(): Unable to write to '$path' for " .
            "template id '$id': $!.");
    $fh->print($self->{content});
    $fh->close();

    # update deploy fields
    my $query = <<SQL;
UPDATE template
SET deployed = ?, deploy_date = ?, deployed_version = ?, testing = ?
WHERE template_id = ?
SQL

    $dbh->do($query, undef, (1, 'now()', $self->{version}, 0, $id));

    add_history(    object => $self, 
                    action => 'deploy',
               );

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

=item * checked_out

=item * checked_out_by

=item * creation_date

=item * deploy_date

=item * deployed

=item * element_class

=item * filename

=item * template_id

=item * testing

=item * version

=back

=over 4

Additional criteria which affect the search results are:

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
    my $limit = delete $args{limit} || '';
    my $offset = delete $args{offset} || '';
    my $order_by = delete $args{order_by} || 'template_id';

    # set search fields
    my $count = delete $args{count} || '';
    my $ids_only = delete $args{ids_only} || '';

    # set bool to determine whether to use $row or %row for binding below
    my $single_column = $ids_only || $count ? 1 : 0;

    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.") if ($count && $ids_only);

    $fields = $count ? 'count(*)' :
      ($ids_only ? 'template_id' : join(", ", keys %template_cols));

    # set up WHERE clause and @params, croak unless the args are in
    # TEMPLATE_RO or TEMPLATE_RW
    my @invalid_cols;
    for my $arg (keys %args) {
        my $like = 1 if $arg =~ /_like$/;
        ( my $lookup_field = $arg ) =~ s/^(.+)_like$/$1/;

        push @invalid_cols, $arg unless exists $template_cols{$lookup_field};

        if ($arg eq 'template_id' && ref $args{$arg} eq 'ARRAY') {
            my $tmp = join(" OR ", map {"template_id = ?"} @{$args{$arg}});
            $where_clause .= " ($tmp)";
            push @params, @{$args{$arg}};
        } else {
            my $and = defined $where_clause && $where_clause ne '' ?
              ' AND' : '';
            if (not defined $args{$arg}) {
                $where_clause .= "$and $lookup_field IS NULL";
            } else {
                $where_clause .= $like ? "$and $lookup_field LIKE ?" :
                  "$and $lookup_field = ?";
                push @params, $args{$arg};
            }
        }
    }

    croak("The following passed search parameters are invalid: '" .
          join("', '", @invalid_cols) . "'") if @invalid_cols;

    # construct base query
    my $query = "SELECT $fields FROM template";

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
    my ($row, @templates);

    # bind fetch calls to $row or %$row
    # a possibly insane micro-optimization :)
    if ($single_column) {
        $sth->bind_col(1, \$row);
    } else {
        $sth->bind_columns(\( @$row{@{$sth->{NAME_lc}}} ));
    }

    # construct template objects from results
    while ($sth->fetchrow_arrayref()) {
        # if we just want count or ids
        if ($single_column) {
            push @templates, $row;
        } else {
            push @templates, bless({%$row}, $self);
        }
    }

    # finish statement handle
    $sth->finish();

    # return number of rows if count, otherwise an array of template ids or
    # objects
    return $count ? $templates[0] : @templates;
}


# Validates the input from new(), and croaks if an arg isn't in %template_args
# or if we don't have 'element_class_name' or 'filename'
sub init {
    my $self = shift;
    my %args = @_;
    my @bad_args;

    for (keys %args) {
        push @bad_args, $_ unless exists $template_args{$_};
    }

    # croak if we've been given invalid args
    croak(__PACKAGE__ . "->init(): The following invalid arguments were " .
          "supplied - " . join' ', @bad_args) if @bad_args;

    # calculate filename
    if (exists $args{element_class_name}) {
        $args{filename} = $args{element_class_name};
    } else {
        croak(__PACKAGE__ . "->init(): Either of the arguments " .
              "'element_class_name' or 'filename' must be supplied.")
          unless exists $args{filename};
    }

    # append file extension, if necessary
    $args{filename} .= '.tmpl' unless $args{filename} =~ /\.tmpl$/;

    $self->hash_init(%args);

    return $self;
}


=item $template = $template->mark_for_testing()

This method sets the testing fields in the template table to allow for the
testing of output of an undeployed template.  If the method call is successful,
the 'testing' and 'testing_by' fields are updated in the db.

The method croaks if the template is not checked out or checked out by another
user.

=cut

sub mark_for_testing {
    my $self = shift;
    my $user_id = $session{user_id};

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


=item $template = $template->prepare_for_edit()

This instance method saves the data currently in the object to the version
table to permit a call to subsequent call to save that does not lose data.

The method croaks if the template is is not checked out, checked out by
another user, or if it can't serialize the template object.

=cut

sub prepare_for_edit {
    my $self = shift;
    my $user_id = $session{user_id};
    my $id = $self->{template_id};
    my $frozen;

    $self->verify_checkout();

    eval {$frozen = freeze($self)};

    # catch any exception thrown by Storable
    croak(__PACKAGE__ . "->prepare_for_edit(): Unable to serialize object " .
          "template id '$id' - $@") if $@;

    my $query = <<SQL;
INSERT INTO template_version (data, template_id, version)
VALUES (?,?,?)
SQL

    my $dbh = dbh();

    $dbh->do($query, undef, ($frozen, $id, $self->{version}));

    return $self;
}


=item $template = $template->revert( $version )

Reverts template object data to that of a previous version.

Reverting to a previous version effectively means deserializing a previous
version from the database and loading it into memory, thus overwriting the
values previously in the object.  A save after reversion results in a new
version number, the current version number never decreases.

The method croaks if the template is not checked out, checked out by another
user, or it can't deserialize the retrieved version.

=cut

sub revert {
    my ($self, $version) = @_;
    my $dbh = dbh();
    my $id = $self->template_id();

    $self->verify_checkout();

    my $query = <<SQL;
SELECT data
FROM template_version
WHERE template_id = ? AND version = ?
SQL

    my @row = $dbh->selectrow_array($query, undef, ($id, $version));

    # preserve version
    my $prsvd_version = $self->{version};

    # overwrite current object
    eval {$self = thaw($row[0])};

    # catch Storable exception
    croak(__PACKAGE__ . "->revert(): Unable to deserialize object for " .
          "template id '$id' - $@") if $@;

    add_history(    object => $self, 
                    action => 'revert',
               );

    # restore version number
    $self->{version} = $prsvd_version;

    return $self;
}


=item $template = $template->save()

Saves template data in memory to the database.

Stores a copy of the objects current contents to the template table. The
version field is incremented on each save.

The method croaks if the template's url is not unique, if the template is not
checked out, checked out by another user, or if the executed SQL affects no
rows in the DB.

=cut

sub save {
    my $self = shift;
    my $user_id = $session{user_id};
    my $id = $self->{template_id} || 0;

    # list of DB fields to insert or update; exclude 'template_id'
    my @save_fields = grep {$_ ne 'template_id'} TEMPLATE_RO, TEMPLATE_RW;

    # calculate url
    my $url =
      (Krang::Category->find(category_id => $self->{category_id}))[0]->url();
    $self->{url} = _build_url($url, $self->{filename});

    # check for duplicate url
    my $template_id = $self->duplicate_check();
    croak(__PACKAGE__ . "->save(): 'url' field is a duplicate of template " .
          "'$template_id'") if $template_id;

    # make sure we've checked out the object
    $self->verify_checkout() if $id;

    # increment version number, set to '1' if this the first call to save
    # for this object
    $self->{version} = exists $self->{version} ? ++$self->{version} : 1;

    # set up query
    my ($query, @tmpl_params);
    if ($self->{version} > 1) {
        $query = "UPDATE template SET " .
          join(', ', map {"$_=?"} @save_fields) . "WHERE template_id = ?";
    } else {
        $query = "INSERT INTO template (" .
          join(",", @save_fields) .
            ") VALUES (?" . ",?" x (scalar @save_fields - 1) . ")";
        $self->{checked_out} = 1;
        $self->{checked_out_by} = $user_id;
        my $t = localtime();
        $self->{creation_date} = $t->strftime("%Y-%m-%d %T");
    }

    # checked_out, deployed, and testing fields cannot be NULL; checked_out
    # is already handled above
    $self->{$_} = $self->{$_} || 0 for (qw/deployed testing/);

    # construct array of bind_parameters
    @tmpl_params = map {$self->{$_}} @save_fields;
    push @tmpl_params, $id if $self->{version} > 1;


    # get database handle
    my $dbh = dbh();

    # croak if no rows are affected
    croak(__PACKAGE__ . "->save(): Unable to save object to DB" .
          ($id ? " for template id '$id'" : ""))
      unless $dbh->do($query, undef, @tmpl_params);

    # get template_id for new objects
    $self->{template_id} = $dbh->{mysql_insertid} unless $id;

    add_history(    object => $self, 
                    action => 'save',
               );

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


=item $true = $template->verify_checkout()

Instance method that verifies the given object is both checked out and checked
out to the current user.

It croaks if the given object is not checked out or if it is checked out by
another user.

Returns '1' on success.

=back

=cut

sub verify_checkout {
    my $self = shift;
    my $id = $self->{template_id};
    my $user_id = $session{user_id};
    my $caller = (caller(1))[3];

    croak("$caller: Object id '$id' is not checked out.")
      unless $self->{checked_out};

    my $cob = $self->{checked_out_by};

    croak("$caller: Object id '$id' is already checked out by user '$cob'")
      unless $cob == $user_id;

    return 1;
}


sub _build_url { (my $url = join('/', @_)) =~ s|/+|/|g; return $url;}

=head1 TO DO

 * Prevent duplicate template objects and paths once Krang::Category is
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

