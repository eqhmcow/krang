package CanoeKayak::cover_double_column;
use strict;
use warnings;
use base 'Krang::ElementClass::Cover';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'cover_double_column',
                 children  => [
    Krang::ElementClass::Text->new(
        name         => 'promo_title',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::Textarea->new(
        name         => 'promo_teaser',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        rows         => 4,
        cols         => 40,
    ),

    Krang::ElementClass::Text->new(
        name         => 'metadata_title',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::Text->new(
        name         => 'metadata_keywords',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::Textarea->new(
        name         => 'metadata_description',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        rows         => 4,
        cols         => 40,
    ),

    'promo_image_small',

    'promo_image_large',

    'left_column',

    'right_column'
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
