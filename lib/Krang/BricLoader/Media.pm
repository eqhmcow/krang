package Krang::BricLoader::Media;

=head1 NAME

Krang::BricLoader::Media -

=head1 SYNOPSIS



=head1 DESCRIPTION



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
use Time::Piece;
use XML::Simple qw(XMLin);

# Internal Modules
###################
use Krang::Conf qw(KrangRoot);
use Krang::Pref;
# BricLoader Modules
use Krang::BricLoader::Category;

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


=item C<< @media = $media->new(path => $filepath) >>

Constructs a new set of media objects from XML in the specified filepath.

=cut

sub new {
    my ($pkg, %args) = @_;
    my $self = bless({},$pkg);
    my $path = $args{path};
    my ($base, @media, $new_path, $ref);

    # set tmpdir
    $self->{dir} = tempdir(DIR => catdir(KrangRoot, 'tmp'));

    croak("File '$path' not found on the system!") unless -e $path;
    $base = (splitpath($path))[2];
    $new_path = catfile($self->{dir}, $base);
    link($path, $new_path);

    $ref = XMLin($new_path,
                 forcearray => ['media'],
                 keyattr => 'hobbittses');
    unlink($new_path);
    croak("\nNo Media defined in input.\n") unless exists $ref->{media};

    for my $m(@{$ref->{media}}) {
        # check for duplicates

        $m = bless($m, $pkg);

        $m->{dir} = $self->{dir};

        # map simple fields
        $m->_map_simple;

        # set category and url
        $m->_build_url;

        # write file
        $m->_write_file();

        push @media, $m;
    }

    return @media;
}


=item C<< $media->serialize_xml(writer => $writer, set => $set) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self, %args) = @_;
    my ($writer, $set) = @args{qw(writer set)};
    local $_;

    # open up <media> linked to schema/media.xsd
    $writer->startTag('media',
                      "xmlns:xsi" =>
                      "http://www.w3.org/2001/XMLSchema-instance",
                      "xsi:noNamespaceSchemaLocation" =>
                      'media.xsd');

    # write media file into data set
    my $path = "media_$self->{media_id}/$self->{filename}";
    $set->add(file => $self->{file_path}, path => $path, from => $self);

    my %media_type = Krang::Pref->get('media_type');

    # basic fields
    $writer->dataElement(media_id   	=> $self->{media_id});
    $writer->dataElement(media_type 	=>
                         $media_type{$self->{media_type_id}});
    $writer->dataElement(title      	=> $self->{title});
    $writer->dataElement(filename   	=> $self->{filename});
    $writer->dataElement(path       	=> $path);
    $writer->dataElement(category_id 	=> $self->{category_id});
    $writer->dataElement(url        	=> $self->{url});
    $writer->dataElement(caption    	=> $self->{caption});
    $writer->dataElement(copyright  	=> $self->{copyright});
    $writer->dataElement(alt_tag    	=> $self->{alt_tag});
    $writer->dataElement(notes      	=> $self->{notes});
    $writer->dataElement(version	=> $self->{version});
    $writer->dataElement(creation_date 	=> $self->{creation_date}->datetime);

    # add category to set
#    $set->add(object => $self->{category}, from => $self);

    # contributors
    my %contrib_type = Krang::Pref->get('contrib_type');
    for my $contrib (@{$self->{contribs}}) {
        $writer->startTag('contrib');
        $writer->dataElement(contrib_id => $contrib->contrib_id);
        $writer->dataElement(contrib_type => 
                             $contrib_type{$contrib->selected_contrib_type()});
        $writer->endTag('contrib');

        $set->add(object => $contrib, from => $self);
    }

    # all done
    $writer->endTag('media');
}


=back

=cut



# Private Methods
##################
# sets category_id and url fields
sub _build_url {
    my $self = shift;
    my $path = $self->{category};
    my ($id, $url) = Krang::BricLoader::Category->get_id_url($path);

    croak("No category id and/or url found associated with Bricolage" .
          " category '$path'") unless ($id && $url);

    $self->{category_id} = $id;
    $self->{url} = join('/', $url, $self->{filename});
    $self->{url} =~ s#/+#/#g;
}

# map bricolage fields to krang equivalents
sub _map_simple {
    my $self = shift;

    # id => media_id
    $self->{media_id} = delete $self->{id};

    # filename
    $self->{filename} = delete $self->{file}->{name};

    # file_path
    $self->{file_path} = catfile($self->{dir}, $self->{filename});

    # name becomes title
    $self->{title} = delete $self->{name};

    # element becomes class
    ($self->{class} = lc delete $self->{element}) =~ s/ /_/g;

    # set media_type_id of that for images....
    $self->{media_type_id} = 1;

    # creation_date
    my $tmp = Time::Piece->strptime($self->{cover_date}, "%FT%TZ");
    $self->{creation_date} = localtime($tmp->epoch);

    # set version to 1
    $self->{version} = 1;
}

# Outputs file content
sub _write_file {
    my ($self) = @_;
    my $path = $self->{file_path};

    my $fh = IO::File->new(">$path") or
      croak("Unable to open '$path' for writing: $!.");
    $fh->print(delete $self->{file}->{data});
    $fh->close;
}





my $quip = <<QUIP;
1
QUIP
