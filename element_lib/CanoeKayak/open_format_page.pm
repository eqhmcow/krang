package CanoeKayak::open_format_page;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'open_format_page',
                 pageable => 1,
                 children  => [
    Krang::ElementClass::Textarea->new(
        name         => 'content',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        rows         => 20,
        cols         => 80,
    )
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
