package Default::image;
use strict;
use warnings;

=head1 NAME

Default::image

=head1 DESCRIPTION

Default image element class for Krang. Image has a caption and copyright
that will override assoicated media caption/copyright if set.  It also has an alignment property.  The height and width of the associated MediaLink image are added to the template data during publication.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'image',
                children => 
                [ 
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

    my %params = ();

    # add width and height of image
    $params{width} = $element->child_data('media')->width()
      if $tmpl->query( name => 'width' );
    $params{height} = $element->child_data('media')->height()
      if $tmpl->query( name => 'height' );
    
    $tmpl->param( \%params );
    
    $self->SUPER::fill_template(%args);
}

1;
