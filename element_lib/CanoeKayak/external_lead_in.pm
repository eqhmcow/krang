package CanoeKayak::external_lead_in;
use strict;
use warnings;
use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'external_lead_in',
                 children  => [
    Krang::ElementClass::Text->new(
        name         => 'title',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::Textarea->new(
        name         => 'teaser',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        rows         => 4,
        cols         => 40,
    ),

    Krang::ElementClass::Text->new(
        name         => 'story_url',
        display_name => 'Story URL',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::PopupMenu->new(
        name         => 'type',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        default      => 'small',
        values      => ['small','large'],
        labels      => {'large' => 'large','small' => 'small'},
    ),

    'image'
                ],
                @_);
    return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;
    my $element = $args{element};
    my $tmpl = $args{tmpl};

    $tmpl->param(link_title => $element->child('title')->data);

    $self->SUPER::fill_template(%args);
}

1;
