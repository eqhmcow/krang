package CanoeKayak::ad_close;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'ad_close',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
