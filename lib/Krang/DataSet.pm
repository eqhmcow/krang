package Krang::DataSet;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Exporter;
use File::Temp qw(tempdir);
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catdir catfile splitpath 
                             file_name_is_absolute rel2abs);
use File::Copy qw(copy);
use File::Find qw(find);
use Krang::ClassLoader Conf => qw(KrangRoot);
use Archive::Tar;
use Cwd qw(fastcwd);
use Krang::ClassLoader Log => qw(debug assert ASSERT);
use Carp qw(croak);
use Krang::ClassLoader 'XML';
use Krang;
use Krang::ClassLoader 'Contrib';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'Template';
use Krang::ClassLoader 'Media';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'XML::Validator';
use List::Util qw(first);

# list of supported classes
our @CLASSES = (qw(Krang::Desk Krang::User Krang::Contrib Krang::Site 
                   Krang::Category Krang::Alert Krang::Group Krang::Media 
                   Krang::Template Krang::Story Krang::Schedule 
                   Krang::ListGroup Krang::List Krang::ListItem ));

# setup exceptions
use Exception::Class 
  'Krang::DataSet::ValidationFailed' => 
    { fields => [ 'errors' ] },
  'Krang::DataSet::InvalidFile' => 
    { fields => [ 'file', 'err' ] },
  'Krang::DataSet::InvalidArchive' => 
    { fields => [ 'file', 'err' ] },
  'Krang::DataSet::DeserializationFailed' => 
    { fields => [] },
  'Krang::DataSet::ImportRejected' => 
    { fields => [ 'set' ] },
  ;

# allow methods to be exported for the BricLoader Classes
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(write _write_index _validate _validate_file);


=head1 NAME

Krang::DataSet - Krang interface to XML data sets

=head1 SYNOPSIS

Creating data sets:

  # create a new data set
  my $set = pkg('DataSet')->new();

  # add an objects to it
  $set->add(object => $story);

  # add an object linked from another object
  $set->add(object => $media, from => $story);

  # add a file (used by media to include their files)
  $set->add(file => $file, path => $path, from => $media);

  # write it out to a kds file
  $set->write(path => "foo.kds");

Loading data sets:

  # load a data set from a file on disk
  my $set = pkg('DataSet')->new(path => "foo.kds");

  # get a list of objects in the set
  my @objects = $set->list();

  # import objects from the set, solving dependencies and updating links
  $set->import_all();

=head1 DESCRIPTION

This modules manages export and import of XML data sets for Krang.
This module is used by krang_export and krang_import.  This module
uses Krang::XML to serialize and deserialize individual objects.

=head1 INTERFACE

=over

=item C<< $set = Krang::DataSet->new(...) >>

Creates a new set object, either empty or by loading an existing data
set previously created with write(). 

May throw a Krang::DataSet::ValidationFailed exception if the archive
is found to contain errors.  See EXCEPTIONS below for details.

Available parameters:

=over

=item path

Specify the path of an existing .kds or .kds.gz file to open.

=item add_callback

Specify a subroutine to be call objects are added to the data set.
The callback will recieve the same arguments as are passed to add().
This is useful if you need to provide progress messages for the user.
Note that the callback will only be called once for each object.

=item import_callback

Specify a subroutine to be call objects are imported from the data
set.  The callback will recieve a single named parameter called object
which contains the object imported.

=back

=cut

sub new {
    my ($pkg, %args) = @_;
    my $self = bless({}, $pkg);

    # create a temp directory to hold in-progress archive
    $self->{dir} = tempdir( DIR => catdir(KrangRoot, 'tmp'));

    # have an add_callback?  else, use an empty sub
    $self->{add_callback} = $args{add_callback} ? 
      $args{add_callback} : sub {};

    # have an import_callback?  else, use an empty sub
    $self->{import_callback} = $args{import_callback} ? 
      $args{import_callback} : sub {};

    if (my $path = $args{path}) {
        croak("Path '$path' does not in .kds or .kds.gz")
          unless $path =~ /\.kds$/ or 
                 $path =~ /\.kds\.gz/;
        croak("Unable to find kds archive '$path'")
          unless -e $path;

        # extract in temp dir
        my $old_dir = fastcwd;
        chdir($self->{dir}) or die "Unable to chdir to $self->{dir}: $!";

	my $z = "";
	$z = "z" if $path =~ /\.gz$/;
	my $result = system("tar -x${z}f ". 
	  (file_name_is_absolute($path) ? $path : rel2abs($path)));
	
        chdir($old_dir) or die "Unable to chdir to $old_dir: $!";
        
        croak("Unable to open kds archive '$path': $?") if ($result);

        # load the index
        $self->_load_index;
                        
        # checks that the index is complete
        $self->_check_index;
    } else {
        $self->{objects} = {};
    }
    return $self;
}

# cleanup tempdir
sub DESTROY {
    my $self = shift;
    rmtree(delete $self->{dir}) if $self->{dir};
}


# runs each file in the kds through a validating parser, matching up
# documents with schemata in /schema
sub _validate {
    my $self = shift;
    local $_;

    my $validator = pkg('XML::Validator')->new();

    # switch into directory with XML
    my $old_dir = fastcwd;
    chdir($self->{dir}) or die "Unable to chdir to $self->{dir}: $!";

    # validate the files
    my %invalid;
    find(sub { 
             return unless /\.xml$/;
             my ($ok, $err) = $validator->validate(path => $_);
             $invalid{$_} = $err unless ($ok);
         }, $self->{dir});

    # get back
    chdir($old_dir) or die "Unable to chdir to $old_dir: $!";

    # cough up error, if we got one    
    Krang::DataSet::ValidationFailed->throw(errors => \%invalid,
                                            message =>
           join("\n",
                map { "File '$_' failed validation: \n$invalid{$_}\n" }
                keys %invalid))
        if %invalid;
}

sub _validate_file {
    my $self = shift;
    my $path = shift;

    my $validator = pkg('XML::Validator')->new();

    my ($ok, $err) = $validator->validate(path => $path);

    # cough up error, if we got one
    Krang::DataSet::ValidationFailed->throw(errors => $err,
                                            message =>
                "File '$path' failed validation: \n$err\n") if $err;

}

=item C<< $set->add(object => $story, from => $self) >>

Adds an object to the data-set.  This operation will also add any
linked objects necessary to later load the object.  If an object
already exists in the data set then this call does nothing.

The C<from> must contain the object calling add() when add() is called
from within serialize_xml().  This is used by Krang::DataSet to
include link information in the index.xml file.

Objects added to data-sets with add() must support serialize_xml() and
deserialize_xml().  For details, see REQUIRED METHODS below.

=item C<< $set->add(file => $file, path => $path) >>

Adds a file to a data-set.  This is used by media to store media files
in the data set.  The file argument must be the full path to the file
on disk.  Path must be the destination path of the file within the
archive.

=cut

sub add {
    my ($self, %args) = @_;
    my $object = $args{object};
    my $from   = $args{from};
    my $file   = $args{file};
    my $path   = $args{path};

    if ($object) {
        my ($class, $id) = _obj2id($object);

        # been there, done that?
        return if $self->{objects}{$class}{$id}{xml};

        # notify add_callback
        $self->{add_callback}->(%args);
        
        # serialize it
        my ($file) = ($class =~ /^Krang::(.*)$/);
        $file = lc($file) . '_' . $id . '.xml';
        my $path = catfile($self->{dir}, $file);
        open(my $fh, '>', $path)
          or croak("Unable to open '$path': $!");

        # register mapping before calling serialize_xml to break cycles
        $self->{objects}{$class}{$id}{xml} = $file;
        
        my $writer = pkg('XML')->writer(fh => $fh);
        $writer->xmlDecl();
        $object->serialize_xml(writer => $writer, set => $self);
        $writer->end();
        close($fh);
        
        if (ASSERT) {
            assert(-e $path, "XML file created");
            assert(-s $path, "XML file has stuff in it");
        }
        
    } elsif ($file and $path and $from) {
        my $full_path = catfile($self->{dir}, $path);
        mkpath((splitpath($full_path))[1]);
        copy($file, $full_path)
          or croak("Unable to copy file '$file' to '$full_path' : $!");
        
        # register file with caller
        my ($from_class, $from_id) = _obj2id($from);
        $self->{objects}{$from_class}{$from_id}{files} ||= [];
        push(@{$self->{objects}{$from_class}{$from_id}{files}}, $path);
     } else {
        croak("Missing required object or file/path params");
    }
}

sub _obj2id {
    my $object = shift;
    my $class = first { $object->isa($_) } @CLASSES;
    my ($id_name) = $class =~ /^Krang::(.*)$/;
    $id_name = lc($id_name) . "_id";
    $id_name = 'list_item_id' if ($id_name eq 'listitem_id');
    $id_name = 'list_group_id' if ($id_name eq 'listgroup_id');

    croak("Unable to determine how to get an id from $class - " . 
          "can($id_name) failed.")
      unless $object->can($id_name);
    return ($class, $object->$id_name);
}

=item C<< @objects = $set->list() >>

This returns a list of objects in the data set.  The list is composed
of two-element arrays listing the class of the object and its id.  For
example:

  @objects = ( [ Krang::Story    => 1 ],
               [ Krang::Story    => 2 ],
               [ Krang::Category => 1 ],
               [ Krang::Site     => 5 ] );

=cut

sub list {
    my $self = shift;
    my @result;
    foreach my $class (keys %{$self->{objects}}) {
        foreach my $id (keys %{$self->{objects}{$class}}) {
            push @result, [ $class, $id ];
        }
    }
    return @result;
}

=item C<< $set->write(path => "foo.kds") >>

=item C<< $set->write(path => "foo.kds.gz", compress => 1) >>

Writes out the set in a kds file named in the path provided.  

May throw a Krang::DataSet::ValidationFailed exception if the archive
is found to contain errors.  See EXCEPTIONS below for details.

=cut

sub write {
    my ($self, %args) = @_;
    my $path     = $args{path};
    my $compress = $args{compress} || 0;
    
    croak("Missing required path arg.") unless $path;
    if ($compress) {
        croak("Path does not end in .kds.gz") unless $path =~ /\.kds\.gz$/;
    } else {
        croak("Path does not end in .kds") unless $path =~ /\.kds$/;
    }

    # go to the kds dir
    my $old_dir = fastcwd;
    chdir($self->{dir}) or die "Unable to chdir to $self->{dir}: $!";

    # open up a new archive
    my $kds = Archive::Tar->new();

    # write the index
    eval { $self->_write_index; };

    if ($@) {
        # gotta get back, regardless of errors
        my $err = $@;
        chdir($old_dir) or die "Unable to chdir to $old_dir: $!";
        die $err;
    }

    # add all files to the tar
    find({ wanted => sub { return unless -f;
                           s!^$self->{dir}/!!;
                           $kds->add_files($_)
                             or croak("Failed to add $_ to KDS : " .
                                      Archive::Tar->error());
                       },
           no_chdir => 1 },
         $self->{dir});

    eval {
        $kds->write((file_name_is_absolute($path) ? 
                     $path : catfile($old_dir, $path)), 
                    $compress ? 9 : 0);
    };
    if ($@) {
        # gotta get back, regardless of errors
        my $err = $@;
        chdir($old_dir) or die "Unable to chdir to $old_dir: $!";
        die $err;
    }
    
    chdir($old_dir) or die "Unable to chdir to $old_dir: $!";

    # Do a validation pass in dev mode to make sure we didn't write
    # junk.  This is better done after writing so that there's
    # something on disk to look at if validation fails.
    $self->_validate if ASSERT;
}

# write out the index XML
sub _write_index {
    my $self = shift;

    # can't write an index for an empty set
    croak("Unable to write index for empty dataset!")
      unless keys %{$self->{objects}};

    open(my $fh, '>','index.xml') or
      croak("Unable to open index.xml: $!");
    my $writer = pkg('XML')->writer(fh => $fh);

    # open up index document
    $writer->xmlDecl();
    $writer->startTag('index',
                      "xmlns:xsi" => 
                        "http://www.w3.org/2001/XMLSchema-instance",
                      "xsi:noNamespaceSchemaLocation" =>
                        'index.xsd');

    # add Krang version
    $writer->dataElement(version => $Krang::VERSION);

    foreach my $class (keys %{$self->{objects}}) {
        $writer->startTag('class', name => $class);
        foreach my $id (keys %{$self->{objects}{$class}}) {
            $writer->startTag('object');
            $writer->dataElement(id  => $id);
            $writer->dataElement(xml => $self->{objects}{$class}{$id}{xml});
            if (my $files = $self->{objects}{$class}{$id}{files}) {
                foreach my $file (@$files) {
                    $writer->dataElement(file => $file);
                }
            }
            $writer->endTag('object');
        }
        $writer->endTag('class');
    }
    $writer->endTag('index');
    $writer->end;
    close($fh);
}

# load index.xml into objects
sub _load_index {
    my $self = shift;
    
    # read in index
    open(my $index, '<', catfile($self->{dir}, 'index.xml')) or 
      croak("Unable to open $self->{dir}/index.xml: $!");
    my $xml = join('', <$index>);
    close $index or die $!;
  
    # parse'm up
    my $data = pkg('XML')->simple(xml => $xml, forcearray => 1);
    my %index;
    foreach my $class_rec (@{$data->{class}}) {
        my $class = $class_rec->{name};
        foreach my $object (@{$class_rec->{object}}) {
            $index{$class}{$object->{id}[0]} = { xml => $object->{xml}[0],
                                                 ($object->{file} ? 
                                                  (files => $object->{file}) : 
                                                  ()),
                                               };
            croak("index.xml refers to file '$object->{xml}[0]' which is ".
                  "not in the archive.")
              unless -e catfile($self->{dir}, $object->{xml}[0]);
        }
    }
    $self->{objects} = \%index;
}


# check the index
sub _check_index {
    my $self = shift;

    foreach my $class (keys %{$self->{objects}}) {
        foreach my $id (keys %{$self->{objects}{$class}}) {
            my $path = catfile($self->{dir}, $self->{objects}{$class}{$id}{xml});
            Krang::DataSet::InvalidArchive->throw(
                 message => "Data set 'index.xml' refers to a file '".
                 $self->{objects}{$class}{$id}{xml} . 
                 "' which does not exist.")
                unless -e $path;
            $self->_validate_file($path);
        }
    }    
}


=item C<< $set->import_all(...) >>

This method tells the set to deserialize all objects in the set and
save them into the current system.  The following optional parameters
are available:

=over

=item no_update

Normally import will attempt to update objects when creating a new
object would create an invalid duplicate.  Set this parameter to 1 and
duplicates will cause the object to fail to import.  (Note that the
exact policy on updates is decided by the individual class'
deserialize_xml() method.)

=item no_uuid

Ignore UUIDs for the purpose of finding matches to update.  This
essentially reverts Krang to its behavior before v2.008.

=item uuid_only

Only use UUIDs for the purpose of finding matches to update.  Matches
using other fields (URL, name, etc) will be treated as errors.

=item skip_classes

Set this option to an array of class names and content for these
classes will not be used to update existing objects.  This is useful
in cases where you wish to update an object without updating objects
it must point to.  For example, to load stories from a set without
altering existing categories:

  $set->import_all(skip_classes => [ 'Krang::Category' ]);

This is currently implemented only for Krang::Category and Krang::Site.

=back

May throw a Krang::DataSet::ValidationFailed exception if the archive
is found to contain errors.  May also throw a
Krang::DataSet::ImportRejects exception if one or more objects failed
to import.  See EXCEPTIONS below for details.

=cut

sub import_all {
    my ($self, %arg) = @_;
    my $objects = $self->{objects};

    # read to go
    $self->{in_import}    = 1;
    $self->{done}         = {};
    $self->{no_update}    = $arg{no_update} || 0;
    $self->{no_uuid}      = $arg{no_uuid} || 0;
    $self->{uuid_only}    = $arg{uuid_only} || 0;
    $self->{skip_classes} = {map { ($_, 1) } @{$arg{skip_classes} || []}};

    # check skip classes
    foreach my $class (keys %{$self->{skip_classes}}) {
        next if $class eq 'Krang::Category';
        next if $class eq 'Krang::Site';
        croak("Found unexpected value in skip_classes list: $class.  Only Krang::Category and Krang::Site are supported.");
    }

    my @failed;

    # process classes in an order least likely to cause backrefs
    foreach my $class (@CLASSES) {
        foreach my $id (keys %{$objects->{$class} || {}}) {
            # might have already loaded through a call to map_id
            next if $self->{done}{$class}{$id};

            # get the ID and store it in 'done'
            eval {
                my $import_id = $self->map_id(class => $class,
                                              id    => $id);
                $self->{done}{$class}{$id} = $import_id;
            };

            # did it fail?
            if ($@ and ref $@ and 
                $@->isa('Krang::DataSet::DeserializationFailed')) {
                push(@failed, { class   => $class, 
                                id      => $id, 
                                message => $@->message });
            } elsif ($@) {
                die $@;
            }
        }
    }

    # all done
    $self->{in_import} = 0;

    # did any imports fail?
    if (@failed) {
        Krang::DataSet::ImportRejected->throw(
             message => join("\n", map { $_->{message} } @failed)
                                             );
    }
}

=item C<< $real_id = $set->map_id(class => "Krang::Foo", id => $id) >>

This call is used during import to return the mapping from an ID in
the import data to an ID on the target system.  This method will croak
if called outside of an import_all() run or if the object can't be
found in the data set.

This call will trigger a deserialization if the object has not yet
been deserialized.

=cut

sub map_id {
    my ($self, %arg) = @_;
    my ($class, $id) = @arg{qw(class id)};
    croak("Missing required 'class' and 'id' params.")
      unless $class and $id;
    croak("Called map_id outside of an import run!")
      unless $self->{in_import};

    # already got it?
    return $self->{done}{$class}{$id} if $self->{done}{$class}{$id};
    
    # deserialize
    my $object = $self->_deserialize($class, $id);
    my ($new_class, $new_id) = _obj2id($object);

    # trigger the callback
    $self->{import_callback}->(object => $object);
    
    # finished
    $self->{done}{$class}{$id} = $new_id;
    return $new_id;
}

sub _deserialize {
    my ($self, $class, $id) = @_;

    # check that we've got a $class with $id
    croak("Can't find XML file for $class with ID $id!") 
      unless $self->{objects}{$class}{$id}{xml};

    my $file = catfile($self->{dir}, $self->{objects}{$class}{$id}{xml});
    open(XML, '<', $file) or croak("Unable to open '$file': $!");
    my $xml = join('',<XML>);
    close(XML) or croak("Unable to close '$file': $!");
    croak("Unable to load XML from $file") unless $xml;

    # are we skipping this clas?
    my $skip = $self->{skip_classes}{$class};

    my $obj = $class->deserialize_xml(xml          => $xml,
                                      set          => $self,
                                      no_update    => $self->{no_update},
                                      no_uuid      => $self->{no_uuid},
                                      uuid_only    => $self->{uuid_only},
                                      skip_update  => $skip);
    croak("Call to $class->deserialize failed!")
      unless $obj;
    croak("Call to $class->deserialize didn't return a $class object!")
      unless ref $obj and UNIVERSAL::isa($obj, $class);

    return $obj;
}

=item C<< $set->register_id(class => $class, id => $id, import_id => $import_id) >>

An object which points to objects which may contain circular
references must call register_id() before calling map_id() on those
objects.  For example, Krang::Story::deserialize_xml() calls
register_id() before deserializing its element tree since those
elements might point to stories which may point back to the original
story.

=cut

sub register_id {
    my ($self, %arg) = @_;
    my ($class, $id, $import_id) = @arg{qw(class id import_id)};
    croak("Missing required 'class', 'id' and 'import_id' params.")
      unless $class and $id and $import_id;
    croak("Called map_id outside of an import run!")
      unless $self->{in_import};

    $self->{done}{$class}{$id} = $import_id;   
}

=item C<< $full_path = $set->map_file(class => $class, id => $id) >>

Get the full path to a file within a set previously added with add().

=cut

sub map_file {
    my ($self, %arg) = @_;
    my $class = $arg{class};
    my $id    = $arg{id};

    my $path = $self->{objects}{$class}{$id}{files}[0];
    return unless $path;

    my $full_path = catfile($self->{dir}, $path);
    croak("Unable to find file '$path' in the data set.")
      unless -e $full_path;
    return $full_path;
}

=back

=head1 EXCEPTIONS

As documented above, the methods in this class may throw the following
exceptions:

=over 4

=item Krang::DataSet::ValidationFailed

This exception indicates that the data set failed schema validation
against the XML Schema files in schema/.  This exception contains a
single field, C<errors>, which is a hash mapping filenames inside the
data set to error message.  Note that C<message> already contains a
reasonable textual representation of the error report.

=item Krang::DataSet::InvalidArchive

If basic sanity checks on the archive fail then this exception will be
returned with C<message> set to an explanation of what went wrong.

=item Krang::DataSet::DeserializeFailed

Modules implementing deserialze_xml() can use this method to
communicate the fact that the import didn't work.  The 'message' field
must be set to a description of why the import failed.

=item Krang::DataSet::ImportRejected

This exeception communicates to the caller of import_all() that one or
more objects failed to import.  The 'message' field will describe the
problems.  The 'set' field will contain a Krang::DataSet object
containing the failed date and their dependencies.  This can be
written out to a file, repaired and then reimported.

=back

=head1 REQUIRED METHODS

Objects which are serialized in data-sets must support two methods:

=over 4

=item C<< $object->serialize_xml(writer => $writer, set => $set) >>

This call must write XML data representing the object using the
provided XML::Writer, or croak on error.  This call should not write
the XML declaration or call C<< $writer->end() >>.

The set parameter includes the Krang::DataSet object where the
serialized object will be packaged.  The object is responsible for
calling C<< $set->add() >> on any objects referenced by ID in the
output XML.

=item C<< $object = Krang::Foo->deserialize_xml(xml => $xml, set => $set, no_update => 0, no_uuid => 0, uuid_only => 0, skip_update => 0); >>

This call must instantiate a new object using the XML provided.  If
C<no_update> is false then the method should make an effort to use the
data to update an existing record if creating it as a new record would
result in an invalid duplicate.

If C<skip_update> is true then the method should not make changes to
an existing object.  Instead, it should return the object unchanged.
New objects should still be created as usual.

If C<no_uuid> is true then UUIDs should not be used to match objects
for update.  If C<uuid_only> is true then only UUIDs should be used
to match.  The default should be to prefer UUID matches and fall-back
to pre-existing keys.

This call must use C<< $set->map_id() >> to request ID mappings for
linked objects (the same ones the object calls $set->add() on during
serialize_xml()).  For example, Krang::Media would use this call to
translate from the category_id in the XML file into the ID to be used
by the media object:

  $category = $set->get_object(class => "Krang::Category",
                               id    => $xml->{category_id});


=back

=cut

1;
