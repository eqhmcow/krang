package CanoeKayak::promo_image_small;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'promo_image_small',
                 children  => [
    Krang::ElementClass::MediaLink->new(name => 'media', min => 1, max => 1, allow_delete => 0, reorderable => 0),

    Krang::ElementClass::Text->new(
        name         => 'caption',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::Text->new(
        name         => 'copyright',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::RadioGroup->new(
        name         => 'image_alignment',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        values      => ['left','right'],
        labels      => {'left' => 'left','right' => 'right'},
    )
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
