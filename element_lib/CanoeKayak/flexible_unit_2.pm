package CanoeKayak::flexible_unit_2;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'flexible_unit_2',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
