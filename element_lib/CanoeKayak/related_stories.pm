package CanoeKayak::related_stories;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'related_stories',
                 children  => [
    'related_story'
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
