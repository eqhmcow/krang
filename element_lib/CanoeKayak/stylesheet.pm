package CanoeKayak::stylesheet;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'stylesheet',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
