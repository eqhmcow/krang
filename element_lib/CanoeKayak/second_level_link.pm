package CanoeKayak::second_level_link;
use strict;
use warnings;
use base 'Krang::ElementClass';

use Krang::Log 'info';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'second_level_link',
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
        maxlength    => 32,
    )
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
