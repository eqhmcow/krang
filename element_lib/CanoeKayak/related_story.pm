package CanoeKayak::related_story;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'related_story',
                 children  => [
    Krang::ElementClass::StoryLink->new(name => 'story',  min => 1, max => 1, allow_delete => 0, reorderable => 0),

    Krang::ElementClass::Text->new(
        name         => 'alternate_title',
        max          => 1,
        size         => 32,
        maxlength    => 256,
    ),

    Krang::ElementClass::Textarea->new(
        name         => 'alternate_teaser',
        max          => 1,
        rows         => 4,
        cols         => 40,
    )
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

1;
