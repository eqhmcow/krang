package CanoeKayak::inset;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'inset',
                 children  => [
    Krang::ElementClass::Textarea->new(
        name         => 'copy',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        rows         => 8,
        cols         => 50,
    )
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
