package CanoeKayak::left_navigation;
use strict;
use warnings;

use base 'Krang::ElementClass::TopLevel';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'left_navigation',
                 children  => [
                               'second_level_link',
                               'top_level_link'
                              ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
