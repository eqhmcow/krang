package Krang::ElementClass::MediaLink;
use strict;
use warnings;

use base 'Krang::ElementClass';

use Krang::MethodMaker
  get_set => [ qw( allow_upload show_thumbnail ) ];
use Krang::Message qw(add_message);

sub new {
    my $pkg = shift;
    my %args = ( allow_upload   => 1,
                 show_thumbnail => 1,
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $html = "";

    # include thumbnail if media is available
    my $media = $element->data();
    if ($media) {
        my $media_id = $media->media_id;
        my $size = $media->file_size;
        $size = $size > 1024 ? int($size / 1024) . 'k' : $size . 'b';
        my $thumbnail_path = $media->thumbnail_path(relative => 1);
        $html .= qq{<div style="padding-bottom: 2px; margin-bottom: 2px; border-bottom: solid #333333 1px">} .
          ($thumbnail_path ? 
           qq{<a href="javascript:preview_media($media_id)"><img src="$thumbnail_path" align=bottom border=0></a> } :
           "") . 
             qq{<a href="javascript:preview_media($media_id)">} . 
               $media->filename . qq{</a> ${size}} . 
                 qq{</div>};
    }

    # add interface for find/upload
    $html .= scalar $query->button(-name    => "find_media_$param",
                                   -value   => "Find Media",
                                   -onClick => "find_media('$param')",
                                  ) 
      . ' or upload a new file: '
        . scalar $query->filefield(-name => $param);

    return $html;
}

# show a thumbnail in view mode
sub view_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $html = "";

    # include thumbnail if media is available
    my $media = $element->data();
    if ($media) {
        my $media_id = $media->media_id;
        my $size = $media->file_size;
        $size = $size > 1024 ? int($size / 1024) . 'k' : $size . 'b';
        my $path = $media->file_path(relative => 1);
        my $thumbnail_path = $media->thumbnail_path(relative => 1);       
        $html .= ($thumbnail_path ? 
                  qq{<a href="javascript:preview_media($media_id)"><img src="$thumbnail_path" align=bottom border=0></a> }  : 
                  "") .
                    qq{<a href="javascript:preview_media($media_id)">} . 
                      $media->filename . qq{</a> ${size}};
    } else {
        $html = "No media object assigned.";
    }
    return $html;
}


sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $filename = $query->param($param);
    return unless defined $filename and length $filename;
    $filename = "$filename"; # otherwise it's a filehandle/string
                             # dualvar which pisses off Storable

    my $fh = $query->upload($param);
    return unless $fh;
    
    my $media = Krang::Media->new(title => $filename,
                                  category_id => 
                                  $element->story()->category()->category_id(),
                                  filename => $filename,
                                  filehandle => $fh);

    # this could be a dup
    eval { $media->save(); };
    if ($@) {
        if (ref $@ and ref $@ eq 'Krang::Media::DuplicateURL') {
            my $err = $@;

            # tell all about it
            add_message(duplicate_media_upload => 
                        id => $err->media_id,
                        filename => $filename);

            # use the dup instead of the new object
            $element->data($err);
        } else {
            die $@;
        }
    } else {
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
    my ($self, %arg) = @_;
    my ($element, $data) = @arg{qw(element data)};
    return $element->data(undef) unless $data;
    my ($media) = Krang::Media->find(media_id => $data);
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
    my $media_id = $set->map_id(class => 'Krang::Media',
                                id    => $import_id);
    $self->thaw_data(element => $element,
                     data    => $media_id);
}

=head1 NAME

Krang::ElementClass::MediaLink - media linking element class

=head1 SYNOPSIS

   $class = Krang::ElementClass::MediaLink->new(name           => "photo",
                                                allow_upload   => 1,
                                                show_thumbnail => 1);

=head1 DESCRIPTION

Provides an element to link to media.  A reference to the media object
is returned from data() for elements of this class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

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
