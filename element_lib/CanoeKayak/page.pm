package CanoeKayak::page;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'page',
                 pageable => 1,
                 children  => [
    Krang::ElementClass::Textarea->new(name         => 'paragraph',
                                       rows         => 8,
                                       cols         => 50,
                                       bulk_edit    => 1,),

    'horizontal_line',

    'image',

    'inset_box',

    'similar_articles_box'
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
