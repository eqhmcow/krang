package Default::image;
use strict;
use warnings;

=head1 NAME

Default::image

=head1 DESCRIPTION

Default image element class for Krang. Image has a caption and copyright
that will override assoicated media caption/copyright if set.
It also has an alignment property.
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

1;
