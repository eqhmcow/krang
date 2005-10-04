package Default::promo_image;
use strict;
use warnings;

=head1 NAME

Default::promo_image

=head1 DESCRIPTION

Default promo image element class for Krang. Image has a caption and copyright
that will override associated media caption/copyright if set.

=cut

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'photo',
                children => 
                [ 
                 pkg('ElementClass::Textarea')->new(name => "caption",
                                                    min => 0,
                                                    max => 1
                                                   ),
                 pkg('ElementClass::Textarea')->new(name => "copyright",
                                                    min => 0,
                                                    max => 1
                                                   ),
                 pkg('ElementClass::MediaLink')->new(name => "media",
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
