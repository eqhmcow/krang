package CanoeKayak::flexible_unit_1;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'flexible_unit_1',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
