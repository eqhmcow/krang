package PBMM::image;
use strict;
use warnings;

=head1 NAME

PBMM::image

=head1 DESCRIPTION

PBMM image element class for Krang. Image has a caption and copyright
that will override assoicated media caption/copyright if set.
It also has aignment property and a protected checkbox.
=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'image',
                children => 
                [ 
                 Krang::ElementClass::CheckBox->new(name => 'protected',
                                                    min => 1,
                                                    max => 1
                                                   ),
                 Krang::ElementClass::PopupMenu->new(name => "alignment",
                                                     min => 1,
                                                     max => 1,
                                                     allow_delete => '0',
                                                     values => [ "Left",
                                                                 "Right"],
                                                     default => "Left"),
                 Krang::ElementClass::Textarea->new(name => "caption",
                                                    min => 0,
                                                    max => 1
                                                   ),
                 Krang::ElementClass::Textarea->new(name => "copyright",
                                                    min => 0,
                                                    max => 1
                                                   ),
                 Krang::ElementClass::MediaLink->new(name => "media",
                                                     required => 1,
                                                     min => 1,
                                                     max => 1,
                                                     allow_delete => 0),
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

    my ($self, %args) = @_;

    my $tmpl      = $args{tmpl};
    my $element   = $args{element};
    my $media = $element->child('media');

    $tmpl->param( image_width => $media->data->width );
    $tmpl->param( image_height => $media->data->height );

     $self->SUPER::fill_template( %args );
}

1;
