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
use Storable qw(freeze thaw);

# Internal Module Depenedencies
use Krang;
use Krang::DB qw(dbh);

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
				 current_version
				 deploy_date
				 deployed
				 description
				 filename
				 name
				 notes
				 testing);
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

This method croaks if an non-extant id is passed or if the user attempting to
check in the object has not previously checked it out.

=cut

sub checkin {
    my $self = shift;
    my @ids = @_;

    return $self;
}


=item $template = $template->checkout()

=item $template = Krang::Template->checkout( $template_id || @template_ids )

Class or instance method for checking out template objects, as a class method
the either a list or single template id must be passed.

This method croaks if an non-extant id is passed or if the object is already
checked out.

=cut

sub checkout {
    my $self = shift;
    my @ids = @_;

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
    $self->save() unless (exists $self->{saved} ||
                          ($self->current_version == $self->{saved}));

    # Write out file
    my $category_path; #Krang::Category->find({id => $self->id()})->get_path();
    my $path = File::Spec->catfile(TEMPLATE_BASEDIR,
                                   $category_path,
                                   $self->filename());
    my $fh = IO::File->new(">$path") or
      Carp::croak(__PACKAGE__ . "->deploy(): Unable to create template " .
                  "path '$path' - $!");
    $fh->print($self->data());
    $fh->close() or Carp::croak(__PACKAGE__ . "->deploy: Unable to close " .
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

    Carp::croak(__PACKAGE__ . "->deploy(): Update of deploy fields failed.")
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

    # croak unless the args are in TEMPLATE_COLS
    my @invalid_cols;
    for (keys %$args) {
        push @invalid_cols, $_ unless exists $template_cols{$_};
    }
    Carp::croak("The following passed search parameters are invalid: '" .
                join("', '", @invalid_cols) . "'") if @invalid_cols;

    # get database handle
    my $dbh = dbh();

    # construct base query
    my $query = "SELECT " . join(", ", TEMPLATE_COLS) .
      " FROM " . TEMPLATE_TABLE;

    # construct where clause based on %args, push bind parameter onto @params
    $query .= " WHERE " . join(" AND ", map {"$_=?"} keys %$args);
    my @params = values %$args;

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
            my $val = $row[$i++];
            $obj->{$_} = defined $val ? $val : undef;
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
    my $row_ref = $dbh->selectrow_arrayref($query, undef, @params) or
      Carp::Croak("No version found matching '$version' for template_id " .
                  "'" . $self->id() . "'");

    # overwrite current object
    # Storable::thaw croaks on its own if there's an error
    $self = thaw($row_ref->[0]);

    return $self;
}


=item $template = $template->save()

Saves template data in memory to the database.

Stores a copy of the objects current contents to the TEMPLATE_TABLE and a
serialized version of this data to TEMPLATE_VERSION.  The version field
(presently: current_version) is incremented on each save and a new row is
inserted into the TEMPLATE_VERSION table.

=back

=cut

sub save {
    my $self = shift;

    # increment version number
    my $version = $self->current_version() || 0;
    $self->current_version(++$version);

    # set up queries
    my (@tmpl_params, $tmpl_query);
    if ($self->current_version > 1) {
        $tmpl_query = "UPDATE TEMPLATE_TABLE SET " .
          join(', ', map {"$_=?"} TEMPLATE_GET_SET) . "WHERE id = ?";
        @tmpl_params = map {no strict; $self->$_;} TEMPLATE_GET_SET;
        push @tmpl_params, $self->id;
    } else {
        $tmpl_query = "INSERT into TEMPLATE_TABLE values(?" .
          ",?" x ((scalar TEMPLATE_COLS) - 1) . ")";
    }
    my $ver_query = "INSERT into VERSION_TABLE value(?" .
      ",?" x ((scalar VERSION_COLS) - 1) . ")";
    my @ver_params;

    return $self;
}


=head1 TO DO



=head1 SEE ALSO

L<Krang>, L<Krang::DB>, L<Krang::Log>, L<Storable>

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
