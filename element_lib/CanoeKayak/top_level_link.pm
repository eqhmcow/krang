package CanoeKayak::top_level_link;
use strict;
use warnings;
use base 'Krang::ElementClass';

use Krang::Log qw(info);

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'top_level_link',
                 children  => [
    Krang::ElementClass::Text->new(
        name         => 'link_text',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::Text->new(
        name         => 'link_destination',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    )
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
