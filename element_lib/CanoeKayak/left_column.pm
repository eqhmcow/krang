package CanoeKayak::left_column;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'left_column',
                 children  => [
    Krang::ElementClass::Text->new(
        name         => 'section_header',
    ),

    Krang::ElementClass::Text->new(
        name         => 'large_section_header',
        max          => 1,
        size         => 32,
    ),

    'horizontal_line',

    'external_lead_in',

    'recent_articles',

    'lead_in'
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
