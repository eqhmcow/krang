package CanoeKayak::related_media;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'related_media',
                 children  => [
    Krang::ElementClass::MediaLink->new(name => 'media', min => 1, max => 1, allow_delete => 0, reorderable => 0)
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
