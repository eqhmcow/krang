package CanoeKayak::global_js;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'global_js',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
