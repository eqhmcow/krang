package CanoeKayak::inset_box;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'inset_box',
                 children  => [
    Krang::ElementClass::Text->new(
        name         => 'title',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        maxlength    => 32,
    ),

    Krang::ElementClass::Textarea->new(name         => 'paragraph',
                                       rows         => 4,
                                       cols         => 40,
                                       bulk_edit    => 1,),

    'horizontal_line',

    'image'
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
