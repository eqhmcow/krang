package Default::image;
use strict;
use warnings;

=head1 NAME

Default::image

=head1 DESCRIPTION

Default image element class for Krang. Image has a caption and
copyright that will override associated media caption/copyright if
set.  It also has an alignment property.  The height and width of the
associated MediaLink image are added to the template data during
publication.

In addition, you may set the image's size using the "Size" selector
whose options may be managed via the Krang List "Image Size". The size
must be specified in the form "336x280", it defines the bounding box
for the resized image.

=cut

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'ElementClass';

use Krang::ClassLoader 'URL';
use Carp qw(croak);
use Imager;
use File::Spec::Functions qw(catfile);

sub new {
    my $pkg = shift;
    my %args = ( name => 'image',
                 children =>
                 [
    pkg('ElementClass::PopupMenu')->new(
        name         => "alignment",
        min          => 1,
        max          => 1,
        values       => [ "Left", "Right"],
        default      => "Left",
        allow_delete => '0',
    ),

    pkg('ElementClass::Textarea')->new(
        name => "caption",
        min  => 0,
        max  => 1
    ),

    pkg('ElementClass::Textarea')->new(
        name => "copyright",
        min  => 0,
        max  => 1
    ),

    pkg('ElementClass::MediaLink')->new(
        name         => "media",
        min          => 1,
        max          => 1,
        allow_delete => 0
    ),

    pkg('ElementClass::ListGroup')->new(
        name         => 'size',
        min          => 1,
        max          => 1,
        list_group   => 'Image Size',
        size         => 1,
        allow_delete => 1,
    ),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element, $order) = @arg{qw(query element order)};
    my ($header, $data);
    if ($header = $element->child('media') and
        $data   = $header->view_data) {
        return $data;
    }
    return '';
}

sub fill_template {
    my ($self, %arg) = @_;
    my ($element, $tmpl, $publisher) = @arg{ qw(element tmpl publisher) };

    my $media = $element->child_data('media');
    return '' unless $media;

    my ($url, $width, $height, %params);

    # maybe resize it
    my ($size_elm) = $element->child('size');
    my $size = $size_elm ? $size_elm->template_data : 'original';

    if ((not $size_elm) or $size =~ /orig/i)  {
        # keep the original size
        $width  = $media->width;
        $height = $media->height;
        $params{media} = pkg('URL')->real_url(object => $media, publisher => $publisher);
    } else {
        # get dimensions for resized image
        my ($x, $y) = split(/x/i, $size);
        croak(__PACKAGE__ . "::fill_template() - image size must be given as 'WIDTHxHEIGHT', but is '$size'")
          unless ($x =~ /\d+/ and $y =~ /\d+/);

        # read original image
        my $orig = Imager->new();
        $orig->read(file => $media->file_path, type => 'jpeg')
          or croak(__PACKAGE__ . "::fill_template() - " . $orig->errstr);

        # create new image
        my $new = $orig->copy();
        $new = $orig->scale(xpixels => $x, ypixels => $y, type => 'min');

        # filename for new image
        my $orig_filename = $media->filename;
        my ($name, $extension) = $orig_filename =~ /(.*)\.([^.]+)$/;
        my $filename = "${name}_${size}.$extension";
        my $path = $publisher->_determine_output_path(object => $publisher->story, category => $publisher->category);
        my $file = catfile($path, $filename);

        # write new image
        $new->write(file => $file)
          or croak(__PACKAGE__ . "::fill_template() - couldn't write resized image '$file': " . $new->errstr);

        # new image's size
        $width  = $new->getwidth;
        $height = $new->getheight;

        # its URL
        my $story_url = pkg('URL')->real_url(object => $publisher->story, publisher => $publisher);
        $story_url .= '/' unless $story_url =~ /\/$/;
        $params{media} = $story_url . $filename;
    }

    # add width and height of image
    $params{width}  = $width  if $tmpl->query(name => 'width' );
    $params{height} = $height if $tmpl->query(name => 'height');


    # alignment, caption, copyright
    $params{alignment} = $element->child_data('alignment');
    $params{caption}   = $element->child_data('caption')   || '';
    $params{copyright} = $element->child_data('copyright') || '';

    $tmpl->param( \%params );
}

1;
