package Krang::BricLoader::DataSet;

=head1 NAME

Krang::BricLoader::DataSet - class that organizes input from other BricLoader
classes into a Krang::DataSet file.

=head1 SYNOPSIS

 use Krang::BricLoader::DataSet;

 # create new DataSet
 my $set = Krang::BricLoader::DataSet->new();

 # add an object
 $set->add(object => $story);

 # add an object linked from another object
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

# Internal Modules
###################


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


=item C<< new >>



=cut

sub new {
}


=item C<< add >>



=cut

sub add {
}


=item C<< write >>



=cut

sub write {
}



=back

=cut



# Private Methods
##################

# Comments:
sub _write_index {
}





my $quip = <<QUIP;

QUIP
