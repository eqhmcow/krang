package CanoeKayak::pixel_tracking;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'pixel_tracking',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
