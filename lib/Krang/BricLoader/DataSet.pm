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
use base 'Krang::DataSet';

# External Modules
###################
use Archive::Tar;
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catdir catfile);
use File::Temp qw(tempdir);

# Internal Modules
###################
use Krang::Conf qw(KrangRoot);
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
deserialize_xml().

=item C<< $set->add(file => $file, path => $path, from => $self) >>

Adds a file to a data-set.  This is used by media to store media files
in the data set.  The file argument must be the full path to the file
on disk.  Path must be the destination path of the file within the
archive.

This method is inherited from Krang::DataSet.

=cut

# overrides Krang::DataSet
sub _obj2id {
    my $object = shift;
    (my $class = ref $object) =~ s/^.+::(.*)$/$1/;
    my $hashname = lc $class;
}

=item C<< $set->write(path => 'bar.kds') >>

=item C<< $set->write(path => 'bar.kds.gz', compress => 1) >>

Writes out the set to the file specified by the path argument.  The method
croaks if the 'path' arg is not supplied, if it is supplied but does not end in
'.kds' or '.kds.gz'.

May throw a Krang::DataSet::ValidationFailed exception if the archive
is found to contain errors.

This method is inherited from Krang::DataSet, See <Krang::DataSet> for more
details.

=back

=cut



# Private Methods
##################

# Comments:
sub _some_method {
}


my $quip = <<QUIP;
April is the cruellest month, breeding
Lilacs out of the dead land, mixing
Memory and desire, stirring
Dull roots with spring rain.

--T. S. Elliot, from 'The Wasteland'
QUIP
