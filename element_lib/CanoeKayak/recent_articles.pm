package CanoeKayak::recent_articles;
use strict;
use warnings;
use base 'Krang::ElementClass';

use Krang::Log qw/critical debug info/;

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'recent_articles',
                 children  => [
    Krang::ElementClass::Text->new(
        name         => 'number',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        maxlength    => 2,
    ),

    Krang::ElementClass::PopupMenu->new(
        name         => 'type',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        default      => 'small',
        values      => ['small','large','no image'],
        labels      => {'no image' => 'no image','large' => 'large','small' => 'small'},
    )
                ],
                @_);
    return $pkg->SUPER::new(%args);
}


sub fill_template {
    my ($self, %args) = @_;

    my $element = $args{element};
    my $publisher = $args{publisher};
    my $story = $element->root;
    my $tmpl = $args{tmpl};

    my $number = $element->child('number')->data;
    my $src;
    my $leadins = [];

    my $type = $element->child('type')->data;

    for (Krang::Story->find(order_by => 'cover_date', limit => 100)) {
        next unless $_->published_version;

        my $e = $_->element;
        my $url = 'http://' . $_->url;
        my $link = $_->title;
        my $image = 0;

        if ($type ne 'no image') {
            my $promo = $e->child("promo_image_$type");
            if ($promo) {
                $src = "http://" . $promo->child('media')->data->url;
                $image = 1;
            }
        }
        push @$leadins, {url => $url, src => $src, link => $link,
                         image => $image};
    }

    $tmpl->param(lead_in_loop => $leadins);

    $self->SUPER::fill_template(%args);
}


1;
