package CanoeKayak::top_column;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'top_column',
                 children  => [
    Krang::ElementClass::Text->new(
        name         => 'section_header',
    ),

    Krang::ElementClass::Text->new(
        name         => 'large_section_header',
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
