package Krang::DataSet;
use strict;
use warnings;

use File::Temp qw(tempdir);
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catdir catfile splitpath);
use File::Copy qw(copy);
use File::Find qw(find);
use Krang::Conf qw(KrangRoot);
use Archive::Tar;
use Cwd qw(fastcwd);
use Krang::Log qw(debug assert ASSERT);
use Carp qw(croak);
use Krang::XML;
use Krang;

# setup exceptions
use Exception::Class 
  'Krang::DataSet::ValidationFailed' => 
    { fields => [ 'errors' ] },
  'Krang::DataSet::InvalidFile' => 
    { fields => [ 'file', 'err' ] };

=head1 NAME

Krang::DataSet - Krang interface to XML data sets

=head1 SYNOPSIS

Creating data sets:

  # create a new data set
  my $set = Krang::DataSet->new();

  # add some objects to it
  $set->add(object => $story);
  $set->add(object => $media);
  $set->add(object => $desk);

  # add a file (used by media to include their files)
  $set->add(file => $file, path => $path);

  # write it out to a kds file
  $set->write(path => "foo.kds");

Loading data sets:

  # load a data set from a file on disk
  my $set = Krang::DataSet->new(path => "foo.kds");

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

=item C<< $set = Krang::DataSet->new() >>

=item C<< $set = Krang::DataSet->new(path => "foo.kds") >>

=item C<< $set = Krang::DataSet->new(path => "foo.kds.gz") >>

Creates a new set object, either empty or by loading an existing data
set previously created with write(). 

May throw a Krang::DataSet::ValidationFailed exception if the archive
is found to contain errors.  See EXCEPTIONS below for details.

=cut

sub new {
    my ($pkg, %args) = @_;
    my $self = bless({}, $pkg);

    # create a temp directory to hold in-progress archive
    $self->{dir} = tempdir( DIR => catdir(KrangRoot, 'tmp'));

    if ($args{path}) {
        croak("Path '$args{path}' does not in .kds or .kds.gz")
          unless $args{path} =~ /\.kds$/ or 
                 $args{path} =~ /\.kds\.gz/;
        croak("Unable to find kds archive '$args{path}'")
          unless -e $args{path};

        my $kds = Archive::Tar->new();
        $kds->read($args{path})
          or croak("Unable to read kds archive '$args{path}' : " . 
                   Archive::Tar->error());

        # extract in temp dir
        my $old_dir = fastcwd;
        chdir($self->{dir}) or die "Unable to chdir to $self->{dir}: $!";
        my $result = $kds->extract_archive($args{path});
        chdir($old_dir) or die "Unable to chdir to $old_dir: $!";
        
        croak("Unable to open kds archive '$args{path}' : " . 
              Archive::Tar->error())
          unless $result;

        # check the archive before going further
        $self->_validate;

        # load the index
        $self->_load_index;
                                         

    } else {
        $self->{objects} = {};
    }
    return $self;
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
    my $data = Krang::XML->simple(xml => $xml, forcearray => 1);
    my %index;
    foreach my $class_rec (@{$data->{class}}) {
        my $class = $class_rec->{name};
        foreach my $object (@{$class_rec->{object}}) {
            $index{$class}{$object->{id}} = $object->{content};
            croak("index.xml refers to file '$object->{content}' which is ".
                  "not in the archive.")
              unless -e catfile($self->{dir}, $object->{content});
        }
    }
    $self->{objects} = \%index;
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

    # switch into directory with XML
    my $old_dir = fastcwd;
    chdir($self->{dir}) or die "Unable to chdir to $self->{dir}: $!";
    
    # prepare links to schema documents so schema processing can work
    my @links;
    find(sub { 
             return unless /\.xsd$/; 
             push(@links, catfile($self->{dir}, $_));
             link(catfile(KrangRoot, "schema", $_), $links[-1])
               or die "Unable to link $_ to $links[-1] : $!";
         }, catdir(KrangRoot, "schema"));

    # validate the files
    my %invalid;
    find(sub { 
             return unless /\.xml$/;
             eval { $self->_validate_file($_) };
             if ($@ and ref $@ and $@->isa('Krang::DataSet::InvalidFile')) {
                 $invalid{$@->file()} = $@->err;
             } elsif ($@) {
                 die $@;
             }
         }, $self->{dir});

    # remove the links
    unlink($_) for @links;

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

# validate a single file, producing an InvalidFile exception if
# validation fails
sub _validate_file {
    my ($self, $file) = @_;

    # FIX: use XML::Xerces if I can ever get it working
    my $DOMCount = catfile(KrangRoot, 'xerces', 'DOMCount');
    local $ENV{LD_LIBRARY_PATH} = catdir(KrangRoot, 'xerces', 'lib') . 
      ($ENV{LD_LIBRARY_PATH} ? ":$ENV{LD_LIBRARY_PATH}" : "");
    my $error = `$DOMCount -n -s -f $file 2>&1`;

    return unless $error =~ /Error/;

    # fixup error message
    $error =~ s{\Q$self->{dir}\E/?}{}g;
    $error =~ s!Errors occurred, no output available!!g;
    $error =~ s!^\s+!!;
    $error =~ s{\s+$}{};

    # toss invalid file exception
    Krang::DataSet::InvalidFile->throw(
         file    => $file,
         err     => $error,
         message => "File '$file' failed validation: \n$error\n");
}

=item C<< $set->add(object => $story) >>

Adds an object to the data-set.  This operation will also add any
linked objects necessary to later load the object.  If an object
already exists in the data set then this call does nothing.

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
    my $file   = $args{file};
    my $path   = $args{path};

    if ($object) {
        my ($class, $id) = _obj2id($object);
        
        # been there, done that?
        return if $self->{objects}{$class}{$id};
        
        # serialize it
        my ($file) = ($class =~ /^Krang::(.*)$/);
        $file = lc($file) . '_' . $id . '.xml';
        my $path = catfile($self->{dir}, $file);
        open(my $fh, '>', $path)
          or croak("Unable to open '$path': $!");
        
        my $writer = Krang::XML->writer(fh => $fh);
        $writer->xmlDecl();
        $object->serialize_xml(writer => $writer, set => $self);
        $writer->end();
        close($fh);
        
        if (ASSERT) {
            assert(-e $path, "XML file created");
            assert(-s $path, "XML file has stuff in it");
        }
        
        $self->{objects}{$class}{$id} = $file;

    } elsif ($file and $path) {
        my $full_path = catfile($self->{dir}, $path);
        mkpath((splitpath($full_path))[1]);
        copy($file, $full_path)
          or croak("Unable to copy file '$file' to '$full_path' : $!");
        print STDERR "WROTE: $full_path\n";
     } else {
        croak("Missing required object or file/path params");
    }
}

sub _obj2id {
    my $object = shift;
    my $class = ref $object;
    my ($id_name) = $class =~ /^Krang::(.*)$/;
    $id_name = lc($id_name) . "_id";
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
    $self->_write_index;

    # add all files to the tar
    find({ wanted => sub { return unless -f;
                           s/^$self->{dir}\/?//;
                           $kds->add_files($_)
                             or croak("Failed to add $_ to KDS : " .
                                      Archive::Tar->error());
                       },
           no_chdir => 1 },
         $self->{dir});

    $kds->write($path);

    # Do a validation pass in dev mode to make sure we didn't write
    # junk.  This is better done after writing so that there's
    # something on disk to look at if validation fails.
    if (ASSERT) {
        eval { $self->_validate };
        if ($@) { 
            chdir($old_dir) or die "Unable to chdir to $old_dir: $!";
            die $@;
        }
    }
    
    # gotta get back
    chdir($old_dir) or die "Unable to chdir to $old_dir: $!";
}

# write out the index XML
sub _write_index {
    my $self = shift;

    open(my $fh, '>','index.xml') or
      croak("Unable to open index.xml: $!");
    my $writer = Krang::XML->writer(fh => $fh);

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
            $writer->startTag('object', id => $id);
            $writer->characters($self->{objects}{$class}{$id});
            $writer->endTag('object');
        }
        $writer->endTag('class');
    }
    $writer->endTag('index');
    $writer->end;
    close($fh);
}

=item C<< $set->import_all() >>

This method tells the set to deserialize all objects in the set and
save them into the current system.

May throw a Krang::DataSet::ValidationFailed exception if the archive
is found to contain errors.  See EXCEPTIONS below for details.

=item C<< $real_id = $set->map_id(class => "Krang::Foo", id => $id) >>

This call is used during import to return the mapping from an ID in
the import data to an ID on the target system.  This method will croak
if called outside of an import_all() run or if the object can't be
found in the data set.

This call will trigger a deserialization if the object has not yet
been deserialized.

=item C<< $object = $set->map_object(class => "Krang::Foo", id => $id) >>

This call is used during import to return the mapping from an ID in
the import data to an object on the target system.  This method will
croak if called outside of an import_all() run or if the object can't
be found in the data set.  Call map_id() if you don't need the full
object.

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

FIX: Implement this!

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

=item C<< $object = Krang::Foo->deserialize_xml(xml => $xml, set => $set, attempt_update => 1); >>

This call must instantiate a new object using the XML provided.  If
C<attempt_update> is set to 1 then the method should make an effort to
use the data to update an existing record if creating it as a new
record would result in an invalid duplicate.

This call must use C<< $set->map_id() >> (or C<< $set->map_object() >>)
to request ID mappings for linked objects (the same ones the object
calls $set->add() on during serialize_xml()).  For example,
Krang::Media would use this call to translate from the category_id in
the XML file into the ID to be used by the media object:

  $category = $set->get_object(class => "Krang::Category",
                               id    => $xml->{category_id});


=back

=cut

1;
