package Krang::DataSet;
use strict;
use warnings;

use File::Temp qw(tempdir);
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catdir catfile);
use File::Find qw(find);
use Krang::Conf qw(KrangRoot);
use Archive::Tar;
use Cwd qw(fastcwd);
use Krang::Log qw(debug assert ASSERT);
use Carp qw(croak);
use Krang::XML;
use Krang;

=head1 NAME

Krang::DataSet - Krang interface to XML data sets

=head2 SYNOPSIS

Creating data sets:

  # create a new data set
  my $set = Krang::DataSet->new();

  # add some objects to it
  $set->add(object => $story);
  $set->add(object => $media);
  $set->add(object => $desk);

  # write it out to a kds file
  $set->write(filename => "foo.kds");

Loading data sets:

  # load a data set from a file on disk
  my $set = Krang::DataSet->new(filename => "foo.kds");

  # get a list of objects in the set
  my @objects = $set->list();

  # import objects from the set, solving dependencies and updating links
  $set->import_all();

  # if there were errors, get a reject set and write it out
  if ($set->import_errors) {
     my $reject = $set->reject_set();
     $reject->write(filename => "reject.kds");
  }

=head1 DESCRIPTION

This modules manages export and import of XML data sets for Krang.
This module is used by krang_export and krang_import.  This module
uses Krang::XML to serialize and deserialize individual objects.

=head1 INTERFACE

=over

=item C<< $set = Krang::DataSet->new() >>

=item C<< $set = Krang::DataSet->new(filename => "foo.kds") >>

=item C<< $set = Krang::DataSet->new(filename => "foo.kds.gz") >>

Creates a new set object, either empty or by loading an existing data
set previously created with write().  This will croak if
inconsistencies are found in the data set archive.

=cut

sub new {
    my ($pkg, %args) = @_;
    my $self = bless({}, $pkg);

    # create a temp directory to hold in-progress archive
    $self->{dir} = tempdir( DIR => catdir(KrangRoot, 'tmp'));

    if ($args{filename}) {
        croak("Filename '$args{filename}' does not in .kds or .kds.gz")
          unless $args{filename} =~ /\.kds$/ or 
                 $args{filename} =~ /\.kds\.gz/;
        croak("Unable to find kds archive '$args{filename}'")
          unless -e $args{filename};

        my $kds = Archive::Tar->new();
        $kds->read($args{filename})
          or croak("Unable to read kds archive '$args{filename}' : " . 
                   Archive::Tar->error());

        # extract in temp dir
        my $old_dir = fastcwd;
        chdir($self->{dir}) or die $!;
        my $result = $kds->extract_archive($args{filename});
        chdir($old_dir) or die $!;
        
        croak("Unable to open kds archive '$args{filename}' : " . 
              Archive::Tar->error())
          unless $result;

        $self->_validate;

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

    # switch into directory with XML
    my $old_dir = fastcwd;
    chdir($self->{dir}) or die $!;
    
    # prepare links to schema documents so schema processing can work
    my @links;
    find(sub { 
             return unless /\.xsd$/; 
             push(@links, catfile($self->{dir}, $_));
             link(catfile(KrangRoot, "schema", $_), $links[-1])
               or die $!;
         }, catdir(KrangRoot, "schema"));

    # validate the files
    find(sub { 
             return unless /\.xml$/;
             $self->_validate_file($_) 
         }, $self->{dir});

    # remove the links
    unlink($_) for @links;

    # get back
    chdir($old_dir) or die $!;
}

# FIX: use XML::Xerces if I can ever get it working
sub _validate_file {
    my ($self, $file) = @_;

    my $DOMCount = catfile(KrangRoot, 'xerces', 'DOMCount');
    local $ENV{LD_LIBRARY_PATH} = catdir(KrangRoot, 'xerces', 'lib') . 
      ($ENV{LD_LIBRARY_PATH} ? ":$ENV{LD_LIBRARY_PATH}" : "");
    my $results = `$DOMCount -n -s -f $file 2>&1`;

    croak("$file failed validation:\n$results\n")
      if ($results =~ /Error/);
}

=item C<< $set->add(object => $story) >>

Adds an object to the data-set.  This operation will also add any
linked objects necessary to later load the object.  If an object
already exists in the data set then this call does nothing.

Objects added to data-sets with add() must support serialize_xml() and
deserialize_xml().  For details, see REQUIRED METHODS below.

=cut

sub add {
    my ($self, %args) = @_;
    my $object = $args{object};
    croak("Missing required object parameter") unless $object;

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
               [ Krang::Category => 3 ],
               [ Krang::Site     => 4 ] );

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
    chdir($self->{dir}) or die $!;

    # open up a new archive
    my $kds = Archive::Tar->new();

    # write the index
    $self->_write_index;

    # do a validation pass in dev mode to make sure we're not writing junk
    $self->_validate if ASSERT;

    # build the KDS
    $kds->add_files('index.xml')
      or croak("Failed to add index.xml to KDS : ".
               Archive::Tar->error());

    # add files to the tar
    foreach my $class (keys %{$self->{objects}}) {
        foreach my $id (keys %{$self->{objects}{$class}}) {
            $kds->add_files($self->{objects}{$class}{$id})
              or croak("Failed to add $self->{objects}{$class}{$id} to KDS : ".
                       Archive::Tar->error());
        }
    }
    $kds->write($path);

    
    # gotta get back
    chdir($old_dir) or die $!;
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
