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
# reference to Krang::BricLoader::DataSet
my $set;



=head1 INTERFACE

=over


=item C<< @media = Krang::BricLoader::Media->new(dataset=>$set, path=>$path) >>

Constructs a new set of media objects from XML in the specified filepath.

=cut

sub new {
    my ($pkg, %args) = @_;
    my $self = bless({},$pkg);
    my $path = $args{path};
    my $xml = $args{xml};
    $set = $args{dataset} || '';
    my ($base, @media, $new_path, $ref);

    # set tmpdir
    $self->{dir} = tempdir(DIR => catdir(KrangRoot, 'tmp'));

    if ($path) {
        croak("File '$path' not found on the system!") unless -e $path;
        $base = (splitpath($path))[2];
        $new_path = catfile($self->{dir}, $base);
        link($path, $new_path);
    } elsif ($xml) {
        $new_path = $xml;
    }

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
    $set->add(file => delete $self->{file}->{data},
              path => $path,
              from => $self);

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


sub DESTROY {
    my $self = shift;
    rmtree($self->{dir}) if $self->{dir};
}


=back

=cut


# Private Methods
##################
# sets category_id and url fields
sub _build_url {
    my $self = shift;
    my $path = $self->{category};
    my ($id, $obj, $url);
    ($id, $url) = Krang::BricLoader::Category->get_id_url($path);

    unless ($id && $url) {
        croak("Valid Krang::BricLoader::DataSet object necessary to add " .
              "objects via Krang::BricLoader::Category->add_new_path!")
          unless (defined $set && ref $set eq 'Krang::BricLoader::DataSet');
        ($id, $url) =
          Krang::BricLoader::Category->add_new_path(set => $set,
                                                    path => $path);
    }

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
    ($self->{class} = delete $self->{element}) =~ s/ /_/g;
    $self->{class} =~ tr/A-Z/a-z/;

    # set media_type_id of that for images....
    $self->{media_type_id} = 1;

    # creation_date
    my $tmp = Time::Piece->strptime($self->{cover_date}, "%FT%TZ");
    $self->{creation_date} = localtime($tmp->epoch);

    # set version to 1
    $self->{version} = 1;
}



my $quip = <<QUIP;
1
QUIP
