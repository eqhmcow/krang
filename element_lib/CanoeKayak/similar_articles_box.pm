package CanoeKayak::similar_articles_box;
use strict;
use warnings;
use base 'Krang::ElementClass';

use Carp qw(verbose croak);
use Krang::Log qw/critical debug info/;

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'similar_articles_box',
                 children  => [
    Krang::ElementClass::Text->new(
        name         => 'number',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        maxlength    => 2,
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

    my $number = $element->child('number')->data or
      croak("A number of articles to link must be specified");

    my @keywords = split /\s+/, $story->child('metadata_keywords')->data;
    my $link_loop;

    for (Krang::Story->find) {
        next if $story->story->story_id == $_->story_id;
        my $e = $_->element;
        my @keys = split /\s+/, $e->child('metadata_keywords')->data;
        for my $key(@keys) {
            if (grep /$key/, @keywords) {
                push @$link_loop, {link => "http://" . $_->url,
                                   title => $_->title};
                last;
            }
        }

        # break out if we already got the right number of articles.
        last if ($link_loop && scalar @$link_loop == $number);
    }

    $tmpl->param(link_loop => $link_loop);

    $self->SUPER::fill_template(%args);
}

1;
