package CanoeKayak::top_navigation;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'top_navigation',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
