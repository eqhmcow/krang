package CanoeKayak::footer;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'footer',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
