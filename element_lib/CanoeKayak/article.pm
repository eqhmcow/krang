package CanoeKayak::article;
use strict;
use warnings;
use base 'Krang::ElementClass::TopLevel';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'article',
                 children  => [
    Krang::ElementClass::Text->new(
        name         => 'large_header',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

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
    ),

    Krang::ElementClass::Textarea->new(
        name         => 'deck',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::Text->new(
        name         => 'metadata_title',
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

    Krang::ElementClass::Textarea->new(
        name         => 'metadata_keywords',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        rows         => 4,
        cols         => 40,
    ),

    Krang::ElementClass::Text->new(
        name         => 'photo_link',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::Text->new(
        name         => 'video_link',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    'page',

    'promo_image_small',

    'promo_image_large'
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
