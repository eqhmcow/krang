package Krang::Template;

=head1 NAME

  Krang::Template - Interface for managing template objects.

=head1 SYNOPSIS

 my $template = Krang::Template->new(category_id => 1,
				     content => '<tmpl_var test>',
				     element_class => 'Class::X');

 # save contents of the object to the DB.
 $template->save();

 # put the object back into circulation for other users
 $template->checkin();

 # save version of object to version table in preparation for edits
 $template->prepare_for_edit();

 # increments to new version
 $template->save();

 # reverts to template revision specified by $version
 $template->revert( $version );

 # remove all references to the object in the template and version tables
 $template->delete();

 # return array of template objects matching criteria in %params
 my @templates = Krang::Template->find( %params );

=head1 DESCRIPTION

Templates determine the form of this systems output.  This module provides a
means of managing this rather crucial resource.

Users have the ability to revert to any previous version of a template. Past
revisions of templates are maintained in a template versioning table, the
current version of a particular template is stored in the template table.

Template data, i.e. the 'content' field, is at present intended to be in
HTML::Template format.  All template filenames will end in the extension
'.tmpl'.

This module interfaces or will interface with Krang::CGI::Template,
Krang::Burner, the FTP interface, and the SOAP interface.

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
use constant TEMPLATE_COLS => qw(template_id
				 category_id
				 checked_out
				 checked_out_by
				 content
				 creation_date
				 deploy_date
				 deployed
				 element_class
				 filename
				 testing
				 version);
use constant TEMPLATE_ARGS => qw(category_id
				 content
				 element_class
				 filename);
use constant VERSION_COLS => qw(data
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
my %template_args = map {$_ => 1} TEMPLATE_ARGS;
my %template_cols = map {$_ => 1} TEMPLATE_COLS;


# Interal Module Dependecies (con't)
# had to define constants before we could use them
use Krang::MethodMaker 	new_with_init => 'new',
  			new_hash_init => 'hash_init',
  			get_set => [TEMPLATE_COLS];


=head1 INTERFACE

=over 4

=item $template = Krang::Template->new( %params )

Constructor provided by Krang::MethodMaker.  Accepts a hash its argument.
Validation of the keys in the hash is performed in the init() method.  The
valid keys to this hash are:

=over 4

=item * category_id

=item * content

=item * element_class

=item * filename

=back

Either of the args 'element_class' or 'filename' must be supplied.

=item $template = $template->checkin()

=item $template = Krang::Template->checkin( $template_id )

Class or instance method for checking in a template object, as a class method
a template id must be passed.

This method croaks if the object is checked out by another user; it does
nothing if the object is not checked out.

=cut

sub checkin {
    my $self = shift;
    my $id = shift || $self->template_id();
    my $dbh = dbh();
    my $user_id = $session{user_id};

    my $query = <<SQL;
SELECT checked_out, checked_out_by
FROM template
WHERE template_id = ?
SQL

    my ($co, $uid) = $dbh->selectrow_arrayref($query, undef, ($id));

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

    $dbh->do($query, undef, ('', '', $id));

    # update checkout fields if this is an instance method call
    if (ref $self eq 'Krang::Template') {
        $self->checked_out('');
        $self->checked_out_by('');
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
    my $id = shift || $self->template_id();
    my $dbh = dbh();
    my $user_id = $session{user_id};
    my $instance_meth;

    if (ref $self eq 'Krang::Template') {
        $instance_meth = 1;
        return $self if ($self->checked_out &&
                         ($self->checked_out_by == $user_id));
    }

    eval {
        # lock template table
        $dbh->do("LOCK TABLES template WRITE");

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


=item $template->delete()

=item Krang::Template->delete( $template_id )

Class or instance method for deleting template objects.  As a class method the
method accepts either a single template id or array object ids.

Deletion means deleting all instances of the object in the version table as
well as the current version in the template.

This method attempts to check out the template before deleting; checkout() will
croak if the object is checked out by another user.

=cut

sub delete {
    my $self = shift;
    my $id = shift || $self->template_id();

    # checkout the template
    $self = Krang::Template->checkout($id);

    my $t_query = "DELETE FROM template WHERE template_id = ?";
    my $v_query = "DELETE FROM template_version WHERE template_id = ?";

    my $dbh = dbh();

    $dbh->do($t_query, undef, ($id));
    $dbh->do($v_query, undef, ($id));
}


=item $template = $template->deploy_to( $dir_path )

Instance method designed to work with Krang::Burner->deploy() to deploy
templates.  The data in the 'content' field is written to $self->filename() in
the '$dir_path' directory.

An error is thrown if the method cannot write to the specified path.

=cut

sub deploy_to {
    my ($self, $dir_path) = @_;
    my $dbh = dbh();
    my $path = File::Spec->catfile($dir_path, $self->filename());
    my $id = $self->template_id();

    # get template content
    my $query = "SELECT content FROM template WHERE template_id = ?";
    my ($data) = $self->content() ||
      $dbh->selectrow_array($query, undef, ($id));

    # write out file
    my $fh = IO::File->new(">$path") or
      croak(__PACKAGE__ . "->deploy_to(): Unable to write to '$path' for " .
            "template id '$id': $!.");
    $fh->print($data);
    $fh->close();

    # update deploy field
    $query = <<SQL;
UPDATE template
SET deployed = ?, deploy_date = now()
WHERE template_id = ?
SQL

    $dbh->do($query, undef, (1, $id));

    return $self;
}


=item @templates  = Krang::Template->find( %params )

Class method that returns the template or templates matching the criteria
provided in $param. The valid keys to the search criteria hash are:

=over 4

=item * category_id

=item * checked_out

=item * checked_out_by

=item * content

=item * creation_date

=item * deploy_date

=item * deployed

=item * element_class

=item * filename

=item * limit

=item * name

=item * offset

=item * order_by

=item * template_id

=item * testing

=item * version

=back

The method croaks if an invalid search criteria is provided.

=cut

sub find {
    my $self = shift;
    my %args = @_;

    # grab limit and offset args
    {
        no strict 'refs';
        $$_ = delete $args{$_} || $find_defaults{$_}
          for (qw/limit offset order_by/);
    }

    # croak unless the args are in TEMPLATE_COLS
    my @invalid_cols;
    for (keys %args) {
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
    $query .= " WHERE " . join(" AND ", map {"$_=?"} keys %args) .
      " $limit ORDER BY $order_by" if keys %args;

    my @params = map {$args{$_}} keys %args;
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);

    # construct template objects from results
    my (@row, @templates);
    while (@row = $sth->fetchrow_array()) {
        my $obj = bless {}, $self;
        my $i = 0;
        @{$obj}{(TEMPLATE_COLS)} = @row;
        push @templates, $obj;
    }

    # finish statement handle
    $sth->finish();

    # return an array or arrayref based on context
    return @templates;
}


# Validates the input from new(), and croaks if an arg isn't in %template_args
# or if we don't have 'element_class' or 'filename'
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
    if (exists $args{element_class}) {
        ($args{filename} = $args{element_class}) =~ s/.*::([^:]+)$/$1/;
    } else {
        croak(__PACKAGE__ . "->init(): Either of the arguments " .
              "'element_class' or 'filename' must be supplied.")
          unless exists $args{filename};
    }

    # lowercase, replace whitespace with '_', append file extension
    $args{filename} = lc $args{filename};
    $args{filename} =~ s/ /_/g;
    $args{filename} .= '.tmpl' unless $args{filename} =~ /\.tmpl$/;

    $self->hash_init(%args);

    return $self;
}


=item $template = $template->mark_for_testing()

This method sets the testing fields in the template table to allow for the
testing of output of an undeployed template.

=cut

sub mark_for_testing {
    my $self = shift;
    my $user_id = $session{user_id};

    # checkout the template if it isn't already
    $self->checkout();

    my @params = (1, $user_id, $self->template_id());

    my $query = <<SQL;
UPDATE template
SET testing = ?, testing_by = ?
WHERE template_id = ?
SQL

    my $dbh = dbh();
    $dbh->do($query, undef, @params);

    return $self;
}


=item $template = $template->prepare_for_edit()

This instance method saves the data currently in the object to the version
table to permit a call to subsequent call to save that does not lose data.

The method croaks if it is unable to serialized the object.

=cut

sub prepare_for_edit {
    my $self = shift;
    my $user_id = $session{user_id};
    my $id = $self->template_id();
    my $frozen;

    # checkout template if it isn't already
    $self->checkout() unless($self->checked_out() &&
                             ($user_id == $self->checked_out_by()));

    eval {$frozen = freeze($self)};

    # catch any exception thrown by Storable
    croak(__PACKAGE__ . "->prepare_for_edit(): Unable to serialize object " .
          "template id '$id' - $@") if $@;

    my $dbh = dbh();

    my @params = ($frozen, $id, $self->version());

    my $query = <<SQL;
INSERT INTO template_version (data, template_id, version)
VALUES (?,?,?)
SQL

    $dbh->do($query, undef, @params);

    return $self;
}


=item $template = $template->revert( $version )

Reverts template object data to that of a previous version.

Reverting to a previous version effectively means deserializing a previous
version from the database and loading it into memory, thus overwriting the
values previously in the object.  A save after reversion results in a new
version number, the current version number never decreases.

The method croaks if it is unable to deserialize the retrieved version.

=cut

sub revert {
    my ($self, $version) = @_;
    my $dbh = dbh();
    my $id = $self->template_id();

    $self->checkout();

    my $query = <<SQL;
SELECT data
FROM template_version
WHERE template_id = ? AND version = ?
SQL

    my @params = ($id, $version);
    my @row = $dbh->selectrow_array($query, undef, @params);

    # preserve version
    my $prsvd_version = $self->version;

    # overwrite current object
    eval {$self = thaw($row[0])};

    # restore version number
    $self->version($prsvd_version);

    # catch Storable exception
    croak(__PACKAGE__ . "->revert(): Unable to deserialize object for " .
          "template id '$id' - $@")
      if $@;

    return $self;
}


=item $template = $template->save()

Saves template data in memory to the database.

Stores a copy of the objects current contents to the template table. The
version field is incremented on each save.

The method croaks if no rows in the database are affected by the executed SQL.

=back

=cut

sub save {
    my $self = shift;
    my $user_id = $session{user_id};
    my $id = $self->template_id || 0;

    # list of DB fields to insert or update; exclude 'template_id'
    my @save_fields = (TEMPLATE_COLS);
    shift @save_fields;

    # make sure we've checked out the object
    $self->checkout() if $id;

    # increment version number
    my $version = $self->version() || 0;
    $self->version(++$version);

    # set up query
    my ($query, @tmpl_params);
    if ($version > 1) {
        $query = "UPDATE template SET " .
          join(', ', map {"$_=?"} @save_fields) . "WHERE template_id = ?";
    } else {
        $query = "INSERT INTO template (" .
          join(",", @save_fields) .
            ") VALUES (?" . ",?" x (scalar @save_fields - 1) . ")";
        $self->checked_out(1);
        $self->checked_out_by($user_id);
        $self->creation_date('now()');
    }

    {
        # turn off strict subs, so we can call methods using fieldnames in
        # TEMPLATE_GET_SET and update checkout and testing fields to ''
        no strict qw/subs/;

        for (qw/deployed deploy_date testing/) {
            $self->$_('');
        }
        @tmpl_params = map {$self->$_} @save_fields;
        push @tmpl_params, $id if $version > 1;
    }

    # get database handle
    my $dbh = dbh();

    # croak if no rows are affected
    croak(__PACKAGE__ . "->save(): Unable to save object to DB" .
          ($id ? " for template id '$id'" : ""))
      unless $dbh->do($query, undef, @tmpl_params);

    # get template_id for new objects
    $self->template_id($dbh->{mysql_insertid}) unless $id;

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
