package CanoeKayak::horizontal_line;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'horizontal_line',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
