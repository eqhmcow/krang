package CanoeKayak::pull_quote;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'pull_quote',
                 children  => [
    Krang::ElementClass::Textarea->new(
        name         => 'quote',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        rows         => 4,
        cols         => 40,
    )
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
