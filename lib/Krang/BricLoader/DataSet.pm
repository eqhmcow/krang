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
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catdir catfile splitpath);
use File::Temp qw(tempdir);

# Internal Modules
###################
use Krang::Conf qw(KrangRoot);
use Krang::DataSet qw(write _validate _validate_file _write_index);
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
our (%category, %category_map, %site, %site_url, %story);
our $category = our $site = our $story = 1;
our %unique_field = ('category' => 'url',
                     'site'	=> 'url',
                     'story'	=> 'url');

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

        # set object id field
        $object->{lc $class . "_id"} = $id;

        # serialize it
        my $file = lc($class) . '_' . $id . '.xml';
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

=back

=cut



# Private Methods
##################
# obtains the category id of the given category's parent
sub _find_parent_site {
    my $cat = shift;
    my @dirs = split(m#/#, $cat->{path});
    my $dir = @dirs >= 3 ? $dirs[$#dirs] : '/';
    my $top = '/' . $dirs[1];
    my $site_id = $category_map{$top} or
      croak("No site found associated with");
    my $parent = join('/', $site_url{$site_id}, @dirs[2..$#dirs - 1]) . '/';
    $parent =~ s#/+#/#g;
    my $parent_id = $category{$parent} || '';
    my $url = join('/', $parent, $dir) . '/';
    $url =~ s#/+#/#g;

    return ($site_id, $url, $parent_id, $dir);
}


# returns a pre-existing or new id to identify object
sub _obj2id {
    my $object = shift;
    (my $class = ref $object) =~ s/^.+::(.*)$/$1/;
    my $id = _obtain_id($class, $object);
    return ($class, $id);
}


# retrieve the arbitrary id for a given object
sub _obtain_id {
    my ($class, $object) = @_;
    my $hashname = my $counter = lc $class;
    my $id;

    if ($hashname eq 'site') {
        # increment site_id
        $id = $site++;

        # set up category to site mapping
        $category_map{$object->{category}} = $id;

        # store site urls keyd by id
        $object->{url} .= '/' if $object->{url} !~ m#/$#;

        $site_url{$id} = $object->{url};
    } elsif ($hashname eq 'category') {
        # get site_id, parent_id, computed path
        my ($site_id, $url, $pid, $dir) = _find_parent_site($object);
        $object->{parent_id} = $pid;
        $object->{site_id} = $site_id;

        # set url, revised path
        $object->{dir} = $dir;
        $object->{url} = $url;

        # get category id
        $id = exists $category{$object->{url}} ? $category{$object->{url}} :
          $category++;

        # store in category hash
        $category{$object->{url}} = $id;
    }

    return $id;
}



sub DESTROY {
    my $self = shift;
    rmtree($self->{dir}) if $self->{dir};

    # DEBUG
    use Data::Dumper;
#    print STDERR "\n", Data::Dumper->Dump([\%category],['category']),
#      "\n\n";
#    print STDERR "\n", Data::Dumper->Dump([\%category_map],['category_map']),
#      "\n\n";
#    print STDERR "\n", Data::Dumper->Dump([\%site],['site']), "\n\n";
#    print STDERR "\n", Data::Dumper->Dump([\%site_url],['site_url']), "\n\n";
#    print STDERR "\n", Data::Dumper->Dump([\%story],['story']), "\n\n";
}


my $quip = <<QUIP;
April is the cruellest month, breeding
Lilacs out of the dead land, mixing
Memory and desire, stirring
Dull roots with spring rain.

--T. S. Elliot, from 'The Wasteland'
QUIP
