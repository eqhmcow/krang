package CanoeKayak::banner_ad;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'banner_ad',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
