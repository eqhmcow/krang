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
use constant TEMPLATE_BASEDIR => 'tmpl';
use constant TEMPLATE_COLS => qw(category_id
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
				 template_id
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
use constant VERSION_COLS => qw(creation_date
				data
				template_id
				template_version_id
				version);

# Globals
##########
# args for find() must be package vars to use symbolic refs...
our ($limit, $offset, $order_by);

# Lexicals
###########
my %find_defaults = (limit => '',
                     offset => 0,
                     order_by => 'template_id');
my %template_cols = map {$_ => 1} TEMPLATE_COLS;


# Interal Module Dependecies (con't)
# had to define constants before we could use them
use Krang::MethodMaker 	new_with_init => 'new',
  			new_hash_init => 'hash_init',
  			get_set => [TEMPLATE_COLS];


=head1 INTERFACE

=over 4

=item C<< $template = Krang::Template->new( %params ) >>

Constructor provided by Krang::MethodMaker.  Accepts a hash its argument.
Validation of the keys in the hash is performed in the init() method.

=item C<< $template = $template->checkin() >>

=item C<< $template = Krang::Template->checkin( $template_id || @template_ids ) >>

Class or instance method for checking in a template object, as a class method
either a list or single template id must be passed.

This method croaks if the user attempting to check in the object has not
previously checked it out.

=cut

sub checkin {
    my $self = shift;
    my @ids = @_ || $self->template_id();
    my $dbh = dbh();
    my $user_id = $session{user_id};

    for (@ids) {
        my $query = <<SQL;
SELECT checked_out, checked_out_by
FROM template
WHERE template_id = ?
SQL
        my ($co, $uid) = $dbh->selectrow_arrayref($query, undef, ($_));

        unless ($co) {
            # prevent unnecessary calls to update
            next;
        } else {
            croak(__PACKAGE__ . "->checkin(): Template id '$_' is checked " .
                  "out by the user '$uid'.")
              if (defined $uid && $uid != $user_id);
        }

        $query = <<SQL;
UPDATE template
SET checked_out = ?, checked_out_by = ?
WHERE template_id = ?
SQL

        $dbh->do($query, undef, ('', '', $_));

    }

    # update checkout fields if this is an instance method call
    if (ref $self eq 'Krang::Template') {
        $self->checked_out('');
        $self->checked_out_by('');
    }

    return $self;
}


=item C<< $template = $template->checkout() >>

=item C<< $template = Krang::Template->checkout( $template_id || @template_ids )>>

Class or instance method for checking out template objects, as a class method
the either a list or single template id must be passed.

This method croaks if the object is already checked out by another user or if
the checkout update query fails.

=cut

sub checkout {
    my $self = shift;
    my @ids = @_ || ($self->template_id());
    my $dbh = dbh();
    my $user_id = $session{user_id};
    my $instance_meth;

    if (ref $self eq 'Krang::Template' && scalar @ids == 1) {
        $instance_meth = 1;
        return $self if ($self->checked_out &&
                         ($self->checked_out_by == $user_id));
    }

    eval {
        # lock template table
        $dbh->do("LOCK TABLES template WRITE");

        for (@ids) {
            my $query = <<SQL;
SELECT checked_out, checked_out_by
FROM template
WHERE template_id = ?
SQL

            my ($co, $uid) = $dbh->selectrow_array($query, undef, ($_));

            if ($co) {
                # no need to call update on a row that's already checked out
                next if $uid == $user_id;

                croak(__PACKAGE__ . "->checkout(): Template id '$_' is " .
                      "already checked out by user '$uid'");
            }

            $query = <<SQL;
UPDATE template
SET checked_out = ?, checked_out_by = ?
WHERE template_id = ?
SQL

            $dbh->do($query, undef, (1, $user_id, $_));
        }

        # unlock template table
        $dbh->do("UNLOCK TABLES");
    };

    if ($@) {
        # unlock the table, so it's not locked forever
        $dbh->do("UNLOCK TABLES");
        croak($@);
    }

    # update checkout fields if this is an instance method call
    if ($instance_meth) {
        $self->checked_out(1);
        $self->checked_out_by($user_id);
    }

    return $self;
}


=item C<< $template = $template->copy_to( $path ) >>

Instance method designed to work with Krang::Burner->deploy() to deploy
templates.  It writes the template 'content' field to the path specified by
$path.

An error is thrown if the method cannot write to the specified path.

=cut

sub copy_to {
    my ($self, $path) = @_;
    my $dbh = dbh();

    # get template content
    my $query = "SELECT content FROM template WHERE template_id = ?";
    my ($data) = $self->content() ||
      $dbh->selectrow_array($query, undef, ($self->template_id()));

    # write out file
    my $fh = IO::File->new(">$path") or
      croak(__PACKAGE__ . "->copy2(): Unable to write to '$path': $!.");
    $fh->print($data);
    $fh->close();

    # update deploy field
    $query = <<SQL;
UPDATE template
SET deployed = ?, deploy_date = now()
WHERE template_id = ?
SQL

    $dbh->do($query, undef, (1, $self->template_id()));

    return $self;
}


=item C<< $template = $template->deploy() >>

This method is responsible for deploying the template associated with the given
template object.  Deployment, at present, consists of the of three tasks:

=over 4

=item * Saving the template to the DB

If the template object has not previously been saved to the database, then it
is saved.

=item * Writing the template to file

The template content is output to the filesystem.  The path computed with
TEMPLATE_BASEDIR, category_id, and filename fields.

=item * Updating the deploy fields in the template table

deployed is set to '1' and deploy_date is set to 'now()'.

=back

This method croaks if any of these three following circumstances occur: if the
module is unnable to write to the template's output path or if the module is
unable to close the template's filehandle.

=cut

sub deploy {
    my $self = shift;

    # Has the object been saved yet?
    $self->save() unless $self->version;

    # Write out file
    # expect to get category path in the following fashion:
    # Krang::Category->find({id => $self->template_id()})->get_path();
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
    my @params = (1, 'now()', $self->template_id());
    my $query = <<SQL;
UPDATE template
SET deployed = ?, deploy_date = now()
WHERE template_id = ?
SQL

    # print out debugging info
#    Krang::debug(__PACKAGE__ . "->deploy() - query:\n$query");
#    Krang::debug(__PACKAGE__ . "->deploy() - parameters:\n" .
#                 join(",", @params));

    $dbh->do($query, undef, @params);

    # update deploy field if this is an instance method call
    $self->{deployed} = 1 if $self->template_id();

    return $self;
}


=item  C<< @templates  = Krang::Template->find( $param ) >>

Class method that returns the template or templates matching the criteria
provided in $param. Any of the fields in TEMPLATE_COLS is an acceptable search
criterion, at least one must be present.

The method croaks if an invalid search criteria is provided, i.e. a field not
found in TEMPLATE_COLS.

=cut

sub find {
    my ($self, $args) = @_;

    # grab limit and offset args
    {
        no strict 'refs';
        $$_ = delete $args->{$_} || $find_defaults{$_}
          for (qw/limit offset order_by/);
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
    my $query = "SELECT " . join(", ", TEMPLATE_COLS) . " FROM template";

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
#    Krang::debug(__PACKAGE__ . "->find() - query:\n$query");
#    Krang::debug(__PACKAGE__ . "->find() - query parameters:\n" .
#                 join(",", @params));

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
    return @templates;
}


=item C<< $template = $template->init() >>

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


=item C<< $template = $template->mark_for_testing() >>

This method sets the testing fields in the template table to allow for the
testing of output of an undeployed template.

=cut

sub mark_for_testing {
    my $self = shift;
    my $user_id = $session{user_id};

    # checkout the template if it isn't already
    $self->checkout();

    my @params = qw/1 $user_id $self->template_id()/;

    my $query = <<SQL;
UPDATE template
SET testing = ?, testing_by = ?
WHERE template_id = ?
SQL

    my $dbh = dbh();
    $dbh->do($query, undef, @params);

    return $self;
}


=item C<< $template = $template->prepare_for_edit() >>

This instance method saves the data currently in the object to the version
table to permit a call to subsequent call to save that does not lose data.

The method croaks if it is unable to serialized the object.

=cut

sub prepare_for_edit {
    my $self = shift;
    my $user_id = $session{user_id};
    my $frozen;

    # checkout template if it isn't already
    $self->checkout() unless($self->checked_out() &&
                             ($user_id == $self->checked_out_by()));

    eval {$frozen = freeze($self)};

    # catch any exception thrown by Storable
    croak(__PACKAGE__ . "->prepare_for_edit(): Unable to serialize object " .
          "- $@") if $@;

    my $dbh = dbh();

    my @params = ($frozen, $self->template_id(), $self->version());

    my $query = <<SQL;
INSERT INTO template_version (creation_date, data, template_id, version)
VALUES (now(),?,?,?)
SQL

    $dbh->do($query, undef, @params);

    return $self;
}


=item C<< $template = $template->revert( $version ) >>

Reverts template object data to that of a previous version.

Reverting to a previous version effectively means deserializing a previous
version from the database and loading it into memory, thus overwriting the
values previously in the object.  A save after reversion results in a new
version number, the current version number never decreases.

The method croaks if it is unable to deserialize the retrieved version.

=cut

sub revert {
    my ($self, $version) = @_;

    $self->checkout();

    # dump of object before overwrite
#    debug(__PACKAGE__ . "->revert(): Attempting to revert to version" .
#          "'$version'");
#    debug(__PACKAGE__ . "->revert(): Dump of object before overwrites\n" .
#          Data::Dumper->Dump([$self],['Object']) . "\n");

    my $query = <<SQL;
SELECT data
FROM template_version
WHERE template_id = ? AND version = ?
SQL

    my @params = ($self->template_id(), $version);

    #log query and params
#    debug(__PACKAGE__ . "->revert(): Revert query\n\t$query\n");
#    debug(__PACKAGE__ . "->revert(): Query bind paramerters\n\t'" .
#          join("','", @params));

    my $dbh = dbh();
    my @row = $dbh->selectrow_array($query, undef, @params);

    # preserve version
    my $prsvd_version = $self->version;

    # overwrite current object
    eval {$self = thaw($row[0])};

    # restore version number
    $self->version($prsvd_version);

    # catch Storable exception
    croak(__PACKAGE__ . "->revert(): Unable to deserialize object - $@")
      if $@;

    return $self;
}


=item C<< $template = $template->save() >>

Saves template data in memory to the database.

Stores a copy of the objects current contents to the template table. The
version field (presently: current_version) is incremented on each save.

The method croaks if the attempt to save is unsuccessful.

=back

=cut

sub save {
    my $self = shift;
    my $user_id = $session{user_id};

    # make sure we've checked out the object
    $self->checkout() if $self->template_id();

    # increment version number
    my $version = $self->version() || 0;
    $self->version(++$version);

    # set up query
    my ($last_param, $query, @tmpl_params);
    if ($self->version > 1) {
        $query = "UPDATE template SET " .
          join(', ', map {"$_=?"} TEMPLATE_GET_SET) . "WHERE template_id = ?";
        $last_param = $self->template_id();
    } else {
        $query = "INSERT into template (" .
          join(",", (TEMPLATE_GET_SET, 'creation_date')) .
            ") values(?" . ",?" x (scalar TEMPLATE_GET_SET) . ")";
        $last_param = 'now()';
        $self->checked_out(1);
        $self->checked_out_by($user_id);
    }

    {
        # turn off strict subs, so we can call methods using fieldnames in
        # TEMPLATE_GET_SET and update checkout and testing fields to ''
        no strict qw/subs/;

        for (qw/deployed deploy_date testing/) {
            $self->$_('');
        }
        @tmpl_params = map {$self->$_} TEMPLATE_GET_SET;
        push @tmpl_params, $last_param;
    }

    # get database handle
    my $dbh = dbh();

    # croak if no rows are affected
    croak(__PACKAGE__ . "->save(): Unable to save object to DB - " .
          $dbh->errstr) unless $dbh->do($query, undef, @tmpl_params);

    # get id in memory...
    unless ($self->template_id()) {
        no warnings;
        my $query = <<SQL;
SELECT template_id
FROM template
WHERE
SQL
        my $i = 0;
        for (TEMPLATE_GET_SET) {
            my $val = $self->$_ || '';
            if ($val) {
                $query .= " AND " if $i++ >= 1;
                $query .= "$_ = '$val'";
            }
        }

        my @row = $dbh->selectrow_array($query) or
          croak(__PACKAGE__ . "->save(): Unable to select object 'id'.");
        $self->template_id($row[0]);
    }

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
