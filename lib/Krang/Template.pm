package Krang::Template;

=head1 NAME

  Krang::Template - Interface for managing template objects.

=head1 SYNOPSIS

 my $template = Krang::Template->new(name => 'test',
				     description => 'description',
				     category_id => 1,
				     notes => 'notes');

 $template->save();

 $template->deploy();

 # increments to new version
 $template->save();

 # reverts to template revision specified by $version
 $template->revert( $version );

 $template->delete();

 # return array of template objects matching criteria in \%params
 my @templates = Krang::Template->find( \%params );

=head1 DESCRIPTION

Templates determine the form of this systems output.  This module provides a
means of managing this rather crucial resource.

Users have the ability to revert to any previous version of a template. Past
revisions of templates are maintained in a template versioning table, the
current version of a particular template is stored in the template table.

This module interfaces or will interface with Krang::CGI::Template, the end
user's means of creating and editing template objects, Krang::Burner, the
module responsible for generating output from the templates, the FTP interface,
a means of uploading templates and hence creating or updating template objects,
and the SOAP interface.

=cut

# Pragmas
use strict;
use warnings;

# External Module Dependencies
use Carp qw(verbose croak);
use Storable qw(freeze thaw);

# Internal Module Depenedencies
use Krang;
use Krang::DB qw(dbh);
use Krang::Session qw(%session);

#
# Package Variables
####################

# Constants
############
use constant TEMPLATE_BASEDIR => '';
use constant TEMPLATE_TABLE => 'template';
use constant VERSION_TABLE => 'template_version';
use constant TEMPLATE_COLS => qw(id
				 category_id
				 checked_out
				 checked_out_by
				 content
				 creation_date
				 deploy_date
				 deployed
				 description
				 filename
				 name
				 notes
				 testing
				 version);
use constant TEMPLATE_GET_SET => qw(category_id
				    checked_out
				    checked_out_by
				    content
				    description
				    name
				    notes
				    testing);
use constant VERSION_COLS => qw(id
				creation_date
				data
				template_id
				version);

# Globals
##########

# Lexicals
###########
my %find_defaults = (limit => '',
                     offset => 0,
                     order_by => 'media_id');
my %template_cols = map {$_ => 1} TEMPLATE_COLS;


# Interal Module Dependecies (con't)
# had to define constants before we could use them
use Krang::MethodMaker 	new_with_init => 'new',
  			new_hash_init => 'hash_init',
  			get_set => [TEMPLATE_GET_SET];


=head1 INTERFACE

=over 4

=item $template = Krang::Template->new( %params )

Constructor provided by Krang::MethodMaker.  Accepts a hash its argument.
Validation of the keys in the hash is performed in the init() method.

=item $template = $template->checkin()

=item $template = Krang::Template->checkin( $template_id || @template_ids )

Class or instance method for checking in a template object, as a class method
either a list or single template id must be passed.

This method croaks if the user attempting to check in the object has not
previously checked it out.

=cut

sub checkin {
    my $self = shift;
    my @ids = @_ || $self->id();
    my $dbh = dbh();
    my $user_id = $session{user_id};

    for (@ids) {
        my $query = <<SQL;
SELECT checked_out, checked_out_by
FROM TEMPLATE_TABLE
WHERE id = ?
SQL
        my $sth = $dbh->prepare($query);
        $sth->execute($_);
        my ($co, $uid) = $sth->fetchrow_arrayref();

        croak(__PACKAGE__ . "->checkin(): Template id '$_' is not checked " .
              "out by the current user.")
          if ($co && $uid != $user_id);

        $query = <<SQL;
UPDATE TEMPLATE_TABLE
SET checked_out = ?, checked_out_by = ?
WHERE id = ?
SQL

        croak(__PACKAGE__ . "->checkin(): Unable to checkin template id '$_'")
          unless $dbh->do($query, undef, ('', '', $_));

    }

    return $self;
}


=item $template = $template->checkout()

=item $template = Krang::Template->checkout( $template_id || @template_ids )

Class or instance method for checking out template objects, as a class method
the either a list or single template id must be passed.

This method croaks if the object is already checked out by another user or if
the checkout update query fails.

=cut

sub checkout {
    my $self = shift;
    my @ids = @_ || ($self->id());
    my $dbh = dbh();
    my $user_id = $session{user_id};
    my (@params, $query, $sth);

    $query = <<SQL;
SELECT checked_out, checked_out_by
FROM TEMPLATE_TABLE
WHERE id = ?
SQL
    $sth = $dbh->prepare($query);

    # make sure each id isn't checked out by another user
    for my $i(0..$#ids) {
        $sth->execute($ids[$i]);
        my ($co, $uid) = $sth->fetchrow_array();

        if ($co) {
            if ($uid == $user_id) {
                $ids[$i] = '';
            } else {
                croak(__PACKAGE__ . "->checkout(): Template id '$ids[$i]' " .
                      "is already checked out by user '$uid'");
            }
        }
    }

    # finish statement handle
    $sth->finish();

    # remove empty entries in the array
    @ids = grep /\d/, @ids;

    # return if everything is already checked out
    return $self unless @ids;

    eval {
        # lock template table
        $dbh->do("LOCK TABLES TEMPLATE_TABLE WRITE");

        for (@ids) {
            @params = (1, $user_id, $_);
            $query = <<SQL;
UPDATE TEMPLATE_TABLE
SET checked_out = ?, checked_out_by = ?
WHERE id = ?
SQL

            croak(__PACKAGE__ . "->checkout(): Checkout failed for template " .
                  "id '$_'")
              unless $dbh->do($query, undef, @params);
        }

        # unlock template table
        $dbh->do("UNLOCK TABLES TEMPLATE_TABLE");
    };

    if ($@) {
        # unlock the table, so it's not locked forever
        $dbh->do("UNLOCK TABLES TEMPLATE_TABLE");
        croak($@);
    }

    return $self;
}


=item $template->delete()

=item Krang::Template->delete( $template_id || @template_ids )

Class or instance method for deleting template objects.  As a class method the
method accepts either a single template id or array object ids.

Deletion means deleting all instances of the object in the version table as
well as the current version in the template.

This method will croak if an object is checked out by another user.

=cut

sub delete {
    my $self = shift;
    my @ids = @_ || ($self->id());

    # checkout the objects
    Krang::Template->checkout(@ids);

    my $t_query = "DELETE FROM TEMPLATE_TABLE WHERE " .
      join(" OR ", map {"id = ?"} @ids);
    my $v_query = "DELETE FROM TEMPLATE_VERSION WHERE " .
      join(" OR ", map {"template_id = ?"} @ids);

    my $dbh = dbh();

    $dbh->do($t_query, undef, @ids);
    $dbh->do($v_query, undef, @ids);
}


=item $template = $template->deploy()

This method is responsible for deploying the template associated with the given
template object.  Deployment, at present, consists of the of three tasks:

=over 4

=item * Saving the template to the DB

If the template object has not previously been saved to the database, then it
is saved.

=item * Writing the template to file

The template content is output to the filesystem.  The path computed with
TEMPLATE_BASEDIR, category_id, and filename fields.

=item * Updating the deploy fields in the TEMPLATE_TABLE

deployed is set to '1' and deploy_date is set to 'now()'.

=back

This method croaks if any of these three following circumstances occur: if the
module is unnable to write to the template's output path, the module is unable
to close the template's filehandle, or if the database query does not affect
any rows.

=cut

sub deploy {
    my $self = shift;

    # Has the object been saved yet?
    $self->save() unless $self->version;

    # Write out file
    # expect to get category path in the following fashion:
    # Krang::Category->find({id => $self->id()})->get_path();
    my $category_path;
    my $path = File::Spec->catfile(TEMPLATE_BASEDIR,
                                   $category_path,
                                   $self->filename());
    my $fh = IO::File->new(">$path") or
      croak(__PACKAGE__ . "->deploy(): Unable to create template path " .
            "'$path' - $!");
    $fh->print($self->content());
    $fh->close() or croak(__PACKAGE__ . "->deploy: Unable to close " .
                          "filehandle after writing - $!");

    # Update deploy fields
    my $dbh = dbh();
    my @params = (1, 'now()', $self->id());
    my $query = <<SQL;
UPDATE TEMPLATE_TABLE
SET deployed = ?, deploy_date = ?
WHERE id = ?
SQL

    # print out debugging info
    Krang::debug(__PACKAGE__ . "->deploy() - query:\n$query");
    Krang::debug(__PACKAGE__ . "->deploy() - parameters:\n" .
                 join(",", @params));

    croak(__PACKAGE__ . "->deploy(): Update of deploy fields failed.")
      unless $dbh->do($query, undef, @params);

    return $self;
}


=item  @templates  = Krang::Template->find( $param )

=item  $templates_ref = Krang::Template->find( $param )

Class method that returns the template or templates matching the criteria
provided in $param. Any of the fields in TEMPLATE_COLS is an acceptable search
criterion, at least one must be present.  In a scalar context an arrayref of
template objects is returned in list context an array.

The method croaks if an invalid search criteria is provided, i.e. a field not
found in TEMPLATE_COLS.

=cut

sub find {
    my ($self, $args) = @_;

    # grab limit and offset args
    my ($limit, $offset, $order_by);
    {
        no strict qw/refs/;
        for (qw/limit offset order_by/) {
            $$_ = delete $args->{$_} || $find_default{$_};
        }
    }


    # croak unless the args are in TEMPLATE_COLS
    my @invalid_cols;
    for (keys %$args) {
        push @invalid_cols, $_ unless exists $template_cols{$_};
    }
    croak("The following passed search parameters are invalid: '" .
          join("', '", @invalid_cols) . "'") if @invalid_cols;

    # get database handle
    my $dbh = dbh();

    # construct base query
    my $query = "SELECT " . join(", ", TEMPLATE_COLS) .
      " FROM " . TEMPLATE_TABLE;

    # construct limit clause
    if ($limit) {
        $limit = "LIMIT $offset, $limit";
    } elsif ($offset) {
        $limit = "LIMIT $offset, -1";
    }

    # construct where clause based on %args, push bind parameter onto @params
    $query .= " WHERE " . join(" AND ", map {"$_=?"} keys %$args) .
      " $limit ORDER BY $order_by";
    my @params = map {$args->{$_}} keys %$args;

    # log $query and @params if assert is on
    # (assert NOT IMPLEMENTED IN Krang::Log yet)
    Krang::debug(__PACKAGE__ . "->find() - query:\n$query");
    Krang::debug(__PACKAGE__ . "->find() - query parameters:\n" .
                 join(",", @params));

    my $sth = $dbh->prepare($query);

    $sth->execute(@params);

    # construct template objects from results
    my (@row, @templates);
    while (@row = $sth->fetchrow_array()) {
        my $obj = bless {}, $self;
        my $i = 0;
        for (TEMPLATE_COLS) {
            $obj->{$_} = $row[$i++];
        }
        push @templates, $obj;
    }

    # finish statement handle
    $sth->finish();

    # return an array or arrayref based on context
    return wantarray ? @templates : \@templates;
}


=item $template = $template->init()

Method for initializing object.  Called after new() required by
Krang::MethodMaker.  This method does nothing except forwarding args to
Krang::MethodMaker->hash_init().

=cut

sub init {
    my $self = shift;
    my %args = @_;

    $self->hash_init(%args);

    return $self;
}


=item $template = $template->mark_for_testing()

This method sets the testing fields in the template database to allow for the
testing of output of an undeployed template.

This method croaks if attempt to update the testing fields is unsuccessful.

=cut

sub mark_for_testing {
    my $self = shift;
    my $user_id = $session{user_id};

    # checkout the template if it isn't already
    $self->checkout() unless($self->checked_out() &&
                             ($user_id == $self->checked_out_by()));

    my @params = qw/1 $user_id $self->id()/;

    my $query = <<SQL;
UPDATE TEMPLATE_TABLE
SET testing = ?, testing_by = ?
WHERE id = ?
SQL

    my $dbh = dbh();

    croak(__PACKAGE__ . "->mark_for_testing(): Unable to set testing flags.")
      unless $dbh->do($query, undef, @params);

    return $self;
}


=item $template = $template->prepare_for_edit()

This instance method saves the data currently in the object to the version
table to permit a call to subsequent call to save that does not lose data.

The method croaks if it is unable to save the serialized object to the version
table.

=cut

sub prepare_for_edit {
    my $self = shift;
    my $user_id = $session{user_id};

    # checkout template if it isn't already
    $self->checkout() unless($self->checked_out() &&
                             ($user_id == $self->checked_out_by()));

    my $frozen = freeze($self) or
      croak(__PACKAGE__ . "->prepare_for_edit(): Unable to serialize object.");

    my $dbh = dbh();

    my @params = ('now()', $frozen, $self->id());

    my $query = <<SQL;
INSERT INTO TEMPLATE_VERSION (creation_date,data)
VALUES (?,?)
WHERE id = ?
SQL

    croak(__PACKAGE__ . "->prepare_for_edit(): Save to version table failed.")
        or $dbh->do($query, undef, @params);

    return $self;
}


=item $template = $template->revert( $version )

Reverts template object data to that of a previous version.

Reverting to a previous version effectively means deserializing a previous
version from the database and loading it into memory, thus overwriting the
values previously in the object.  A save after reversion results in a new
version number, the current version number never decreases.

The method croaks if a version corresponding to the version argument for the
current object is not found in the DB, or if we are unable to deserialize the
retrieved version.

=cut

sub revert {
    my ($self, $version) = @_;

    # dump of object before overwrite
    debug(__PACKAGE__ . "->revert(): Attempting to revert to version" .
          "'$version'");
    debug(__PACKAGE__ . "->revert(): Dump of object before overwrites\n" .
          Data::Dumper->Dump([$self],['Object']) . "\n");

    my $query = <<SQL;
SELECT b.data
FROM TEMPLATE_TABLE a, TEMPLATE_VERSION b
WHERE a.id = ? AND a.id=b.template_id AND b.version = ?
SQL

    my @params = qw/$self->id() $version/;

    #log query and params
    debug(__PACKAGE__ . "->revert(): Revert query\n\t$query\n");
    debug(__PACKAGE__ . "->revert(): Query bind paramerters\n\t'" .
          join("','", @params));

    my $dbh = dbh();
    my $row_ref = $dbh->do($query, undef, @params) or
      croak("No version found matching '$version' for template_id " .
            "'" . $self->id() . "'");

    # overwrite current object
    $self = thaw($row_ref->[0]) or
      croak(__PACKAGE__ . "->revert(): Unable to deserialize object.");

    return $self;
}


=item $template = $template->save()

Saves template data in memory to the database.

Stores a copy of the objects current contents to the TEMPLATE_TABLE. The
version field (presently: current_version) is incremented on each save.

The method croaks if the attempt to save is unsuccessful.

=back

=cut

sub save {
    my $self = shift;
    my $user_id = $session{user_id};

    # make sure we've checked out the object
    $self->checkout() unless($self->checked_out() &&
                             ($user_id == $self->checked_out_by()));

    # increment version number
    my $version = $self->version() || 0;
    $self->version(++$version);

    # set up query
    my ($last_param, $query, @tmpl_params);
    if ($self->version > 1) {
        $query = "UPDATE TEMPLATE_TABLE SET " .
          join(', ', map {"$_=?"} TEMPLATE_GET_SET) . "WHERE id = ?";
        $last_param = $self->id;
    } else {
        $query = "INSERT into TEMPLATE_TABLE (" .
          join(",", (TEMPLATE_GET_SET, 'creation_date')) .
            ") values(?" . ",?" x (scalar TEMPLATE_GET_SET) . ")";
        $last_param = 'now()';
    }

    {
        # turn off strict subs, so we can call methods using fieldnames in
        # TEMPLATE_GET_SET and update checkout and testing fields to ''
        no strict qw/subs/;

        for (qw/checked_out checked_out_by testing/) {
            $self->$_('');
        }
        @tmpl_params = map {$self->$_} TEMPLATE_GET_SET, $last_param;
    }

    # get database handle
    my $dbh = dbh();

    # croak if no rows are affected
    croak(__PACKAGE__ . "->save(): Unable to save object to DB - " .
          $dbh->errstr) unless $dbh->do($query, undef, @tmpl_params);

    return $self;
}


=head1 TO DO

=head1 SEE ALSO

L<Krang>, L<Krang::DB>, L<Krang::Log>

=cut

{
    no warnings;
    q|Some say the world will end in fire;
Some say in ice.
From what I've tasted of desire
I hold with those who favor fire.
But if it had to perish twice,
  I think I know enough of hate
    To know that for destruction ice
      Is also great
        And would suffice
          - Robert Frost|;
}
