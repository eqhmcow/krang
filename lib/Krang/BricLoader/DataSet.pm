package Krang::BricLoader::DataSet;

=head1 NAME

Krang::BricLoader::DataSet - class that organizes input from other BricLoader
classes into a Krang::DataSet file.

=head1 SYNOPSIS

 use Krang::BricLoader::DataSet;

 # create new DataSet
 my $set = Krang::BricLoader::DataSet->new();

 # all sites must be obtained before any underlying assets can be added
 my $site = Krang::BricLoader::Site->new(xml => \$xml_ref);
 $set->add(object => $site);

 # now add any object
 $set->add(object => $contributor);
 $set->add(object => $element);
 $set->add(object => $template);
 $set->add(object => $story);
 $set->add(object => $category);	# croaks if this not related to a
					# site or category already in the
					# dataset

 # add an object linked from another object
 $set->add(object => $category, from => $site);
 $set->add(object => $contributor, from => $story);
 $set->add(object => $media, from => $story);
 $set->add(object => $storyb, from => $story);

 # add a media file
 $set->add(file => $file, path => $path, from => $media);

 # write it out to a file
 $set->write(path => "bar.kds");

 # get a unique asset id
 $set->get_id(object => $object);

=head1 DESCRIPTION

This module represents an attempt to recreate the Krang::DataSet metaphor for
the purpose of generating a valid Krang dataset from Bricolage input data.  The
principal differences between this and Krang::DataSet are that this module
lacks any facility to import a dataset it has created (Krang::DataSet already
serves that purpose) and of course that the serialized input is derived from
Bricolage instead of Krang objects.  The classes
Krang::BricLoader::Category, Contributor, Media, Site, Story, and Template
replicate the serialization provided by their analogous Krang classes while not
requiring a means to deserialize the data.

=cut



#
# Pragmas/Module Dependencies
##############################
# Pragmas
##########
use strict;
use warnings;

# External Modules
###################
use Carp qw(verbose croak);
use Cwd qw(fastcwd);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catdir catfile file_name_is_absolute rel2abs
			     splitpath);
use File::Temp qw(tempdir);

# Internal Modules
###################
use Krang::Conf qw(KrangRoot);
use Krang::Log qw(debug assert ASSERT);
use Krang::XML;
# BricLoader Modules :)
use Krang::BricLoader::Category;
use Krang::BricLoader::Site;
use Krang::BricLoader::Story;

#
# Package Variables
####################
# Constants
############

# Globals
##########

# Lexicals
###########




=head1 INTERFACE

=over

=item C<< $set = Krang::BricLoader::DataSet->new() >>

Creates a new, empty DataSet object.

=cut

sub new {
    my $self = bless({}, shift);

    # create temp dir for intermediate output
    $self->{dir} = tempdir(DIR => catdir(KrangRoot, 'tmp'));

    return $self;
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

        # serialize it
        my ($file) = ($class =~ /^Krang::(.*)$/);
        $file = lc($file) . '_' . $id . '.xml';
        my $path = catfile($self->{dir}, $file);
        open(my $fh, '>', $path)
          or croak("Unable to open '$path': $!");

        # register mapping before calling serialize_xml to break cycles
        $self->{objects}{$class}{$id}{xml} = $file;

        my $writer = Krang::XML->writer(fh => $fh);
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

        # delete media tmpdir
        rmtree($from->{dir});

        # register file with caller
        my ($from_class, $from_id) = _obj2id($from);
        $self->{objects}{$from_class}{$from_id}{files} ||= [];
        push(@{$self->{objects}{$from_class}{$from_id}{files}}, $path);
     } else {
        croak("Missing required object or file/path params");
    }
}


=item C<< $set->write(path => 'bar.kds') >>

=item C<< $set->write(path => 'bar.kds.gz', compress => 1) >>

This method is imported from Krang::DataSet, See <Krang::DataSet> for more
details.

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
                           s!^$self->{dir}/!!;
                           $kds->add_files($_)
                             or croak("Failed to add $_ to KDS : " .
                                      Archive::Tar->error());
                       },
           no_chdir => 1 },
         $self->{dir});

    $kds->write((file_name_is_absolute($path) ?
                 $path : catfile($old_dir, $path)),
                $compress ? 9 : 0);

    # gotta get back
    chdir($old_dir) or die "Unable to chdir to $old_dir: $!";

    # Do a validation pass in dev mode to make sure we didn't write
    # junk.  This is better done after writing so that there's
    # something on disk to look at if validation fails.
#    $self->_validate if ASSERT;
}

=back

=cut

# Private Methods
##################
# returns a pre-existing or new id to identify object
sub _obj2id {
    my $object = shift;
    (my $class = ref $object) =~ s/^Krang::BricLoader::(.*)$/$1/;
    my $field = lc $class . "_id";
    my $id = $object->{$field};
    $class = "Krang::" . ucfirst $class;
    return ($class, $id);
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

sub DESTROY {
    my $self = shift;
    rmtree($self->{dir}) if $self->{dir};
}


my $quip = <<QUIP;
April is the cruellest month, breeding
Lilacs out of the dead land, mixing
Memory and desire, stirring
Dull roots with spring rain.

--T. S. Elliot, from 'The Wasteland'
QUIP
