package Krang::ElementClass::MediaLink;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass';
use Krang::ClassLoader Log  => qw(debug info critical assert ASSERT);
use Krang::ClassLoader Conf => qw(PreviewSSL);
use Krang::ClassLoader 'URL';
use Krang::ClassLoader Localization => qw(localize);

# For *Link hard find feature
use Storable qw(nfreeze);
use MIME::Base64 qw(encode_base64);

use Krang::ClassLoader MethodMaker => get_set => [qw( allow_upload show_thumbnail )],
  hash                             => [qw( find )];

use Krang::ClassLoader Message => qw(add_alert);

sub new {
    my $pkg  = shift;
    my %args = (
        allow_upload   => 1,
        show_thumbnail => 1,
        lazy_loaded    => 1,
        @_
    );

    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $html = "";

    # include thumbnail if media is available
    my $media = $element->data();
    if ($media) {
        my $media_id = $media->media_id;
        my $size     = $media->file_size;
        $size = $size > 1024 ? int($size / 1024) . 'k' : $size . 'b';
        my $thumbnail_path = $media->thumbnail_path(relative => 1);
        $html .=
          qq{<div style="padding-bottom: 2px; margin-bottom: 2px; border-bottom: solid #333333 1px">}
          . (
            $thumbnail_path
            ? qq{<a href="" class="media-preview-link" name="media_$media_id"><img src="$thumbnail_path" align=bottom border=0 class="thumbnail"></a> }
            : ""
          )
          . qq{<a href="" class="media-preview-link" name="media_$media_id">}
          . $media->filename
          . qq{</a> ${size}}
          . qq{</div>};
    }

    # add interface for find/upload
    $html .= scalar $query->button(
        -name    => "find_media_$param",
        -value   => localize("Find Media"),
        -onClick => "find_media('$param')",
        -class   => "button"
    );
    if ($self->allow_upload) {
        $html .= ' '
          . localize('or upload a new file:') . ' '
          . scalar $query->filefield(-name => $param)
          . '&nbsp;';
    }

    # Add hard find parameters
    my $find = encode_base64(nfreeze(scalar($self->find())));
    my $hard_find_param = $query->hidden("hard_find_$param", $find);
    $html .= $hard_find_param;

    return $html;
}

# due to the unusual way that media links get their data, a story link
# is invalid only if required and it doesn't already have a value.
sub validate {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    return 1 unless $self->{required};
    return 1 if $element->data or $query->param($param);
    return (0, localize($self->display_name) . ' ' . localize('requires a value.'));
}

# show a thumbnail in view mode
sub view_data {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $html = "";

    # include thumbnail if media is available
    my $media = $element->data();
    if ($media) {
        my $media_id = $media->media_id;
        my $size     = $media->file_size;
        $size = $size > 1024 ? int($size / 1024) . 'k' : $size . 'b';
        my $path           = $media->file_path(relative      => 1);
        my $thumbnail_path = $media->thumbnail_path(relative => 1);
        $html .= (
            $thumbnail_path
            ? qq{<a href="" class="media-preview-link" name="media_$media_id"><img src="$thumbnail_path" align=bottom border=0 class="thumbnail"></a> }
            : ""
          )
          . qq{<a href="" class="media-preview-link" name="media_$media_id">}
          . $media->filename
          . qq{</a> ${size}};
    } else {
        $html = localize("No media object assigned.");
    }
    return $html;
}

sub load_query_data {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $filename = $query->param($param);
    return unless defined $filename and length $filename;
    $filename = "$filename";    # otherwise it's a filehandle/string
                                # dualvar which pisses off Storable

    # Coerce a reasonable name from what we get
    my @filename_parts = split(/[\/\\\:]/, $filename);
    $filename = $filename_parts[-1];

    my $fh = $query->upload($param);
    return unless $fh;

    # find the category_id for the containing object
    my $object = $element->object;
    my $category_id;
    if ($object->isa('Krang::Story') || $object->isa('Krang::Media')) {
        $category_id = $object->category()->category_id();
    } elsif ($object->isa('Krang::Category')) {
        $category_id = $object->category_id();
    } else {
        croak("Expected a story, media object or category in element->object!");
    }

    my %media_types    = pkg('Pref')->get('media_type');
    my @media_type_ids = keys(%media_types);

    my $media = pkg('Media')->new(
        title         => $filename,
        category_id   => $category_id,
        filename      => $filename,
        filehandle    => $fh,
        media_type_id => $media_type_ids[0]
    );

    # this could be a dup
    eval { $media->save(); };
    if ($@) {
        if (ref $@ and ref $@ eq 'Krang::Media::DuplicateURL') {
            my $err = $@;

            # tell all about it
            add_alert(
                duplicate_media_upload => id => $err->media_id,
                filename               => $filename
            );

            # use the dup instead of the new object
            $element->data(pkg('Media')->find(media_id => $err->media_id));
        } else {
            die $@;
        }
    } else {

        # preview the image so it's available on the story that's being worked on
        $media->preview();

        # the save worked
        $element->data($media);
    }
}

# store ID of object in the database
sub freeze_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    my $media = $element->data;
    return undef unless $media;
    return $media->media_id;
}

# load object by ID, ignoring failure since the object might have been
# deleted
sub thaw_data {
    my ($self,    %arg)  = @_;
    my ($element, $data) = @arg{qw(element data)};
    return $element->data(undef) unless $data;
    my ($media) = pkg('Media')->find(media_id => $data);
    return $element->data($media);
}

# do the normal XML serialization, but also include the linked media
# object in the dataset
sub freeze_data_xml {
    my ($self, %arg) = @_;
    my ($element, $writer, $set) = @arg{qw(element writer set)};
    $self->SUPER::freeze_data_xml(%arg);

    # add object
    my $media = $element->data;
    $set->add(object => $media, from => $element->object) if $media;
}

# translate the incoming media ID into a real ID
sub thaw_data_xml {
    my ($self, %arg) = @_;
    my ($element, $data, $set) = @arg{qw(element data set)};

    my $import_id = $data->[0];
    return unless $import_id;
    my $media_id = $set->map_id(
        class => pkg('Media'),
        id    => $import_id
    );
    assert(pkg('Media')->find(media_id => $media_id, count => 1))
      if ASSERT;
    assert((pkg('Media')->find(media_id => $media_id))[0]->url)
      if ASSERT;
    $self->thaw_data(
        element => $element,
        data    => $media_id
    );
}

# overriding Krang::ElementClass::template_data
# checks the publish status, returns url or preview_url, depending.
sub template_data {
    my $self = shift;
    my %args = @_;

    return $args{publisher}->url_for(
        object => $args{element}->data,
    );
}

#
# If fill_template() has been called, a template exists for this element.
# Populate it with available attributes - story title & url.
#
# See Krang::ElementClass->fill_template for more information.
#
sub fill_template {
    my ($self, %args) = @_;
    my $tmpl      = $args{tmpl};
    my $publisher = $args{publisher};
    my $element   = $args{element};
    my $data      = $element->data;

    return unless $data;

    my %params = ();
    my $width  = $data->width;
    my $height = $data->height;

    $params{url} = $element->template_data(publisher => $publisher);
    $params{title}   = $data->title   if $tmpl->query(name => 'title');
    $params{caption} = $data->caption if $tmpl->query(name => 'caption');
    $params{width}   = $width         if $tmpl->query(name => 'width');
    $params{height}  = $height        if $tmpl->query(name => 'height');
    $params{image_dimensions} = "width='$width' height='$height'"
      if $tmpl->query(name => 'image_dimensions');

    $tmpl->param(\%params);
}

=head1 NAME

Krang::ElementClass::MediaLink - media linking element class

=head1 SYNOPSIS

   $class = pkg('ElementClass::MediaLink')->new(name           => "photo",
                                                allow_upload   => 1,
                                                show_thumbnail => 1);

=head1 DESCRIPTION

Provides an element to link to media.  A reference to the media object
is returned from data() for elements of this class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

In addition to the normal interfaces, Krang::ElementClass::MediaLink also 
supports a "find" parameter.  This parameter allows you to specify a
"hard filter" which is used to limit the scope of the universe of 
stories from which the user may select.  For example:

  # Only images
  my $c = Krang::ElementClass::MediaLink->new(
                name => 'associated_image',
                find => { media_type_id => 1 }
  );


  # Only images about cats
  my $c = Krang::ElementClass::MediaLink->new(
                name => 'associated_image',
                find => { media_type_id => 1,
                          filename_like => '%cats%' }
  );

Any find parameters which are permitted by Krang::Media may be used
by Krang::ElementClass::MediaLink's "find" parameter.


=over 4

=item allow_upload

Show an upload box in the editing interface to create new Media
objects inline.  Defaults to 1.

=item show_thumbnail

Show a thumbnail of the media object in the editing and viewing
interface.  Defaults to 1.

=back

=cut

1;
