package CanoeKayak::right_col_ads;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'right_col_ads',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
