package CanoeKayak::cover_multi_page;
use strict;
use warnings;
use base 'Krang::ElementClass::Cover';

use Krang::Log qw/critical debug info/;

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'cover_multi_page',
                 pageable => 1,
                 children  => [
    Krang::ElementClass::Text->new(
        name         => 'leadins_per_page',
        display_name => 'Lead-Ins Per Page',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::Textarea->new(
        name         => 'metadata_description',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        rows         => 4,
        cols         => 40,
    ),

    Krang::ElementClass::Textarea->new(
        name         => 'metadata_keywords',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        rows         => 4,
        cols         => 40,
    ),

    Krang::ElementClass::Text->new(
        name         => 'metadata_title',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::Textarea->new(
        name         => 'promo_teaser',
        min          => 1,
        max          => 1,
        allow_delete => 0,
        rows         => 4,
        cols         => 40,
    ),

    Krang::ElementClass::Text->new(
        name         => 'promo_title',
        min          => 1,
        max          => 1,
        allow_delete => 0,
    ),

    Krang::ElementClass::Text->new(
        name         => 'large_header',
    ),

    Krang::ElementClass::Text->new(
        name         => 'section_header',
    ),

    'horizontal_line',

    'promo_image_small',

    'external_lead_in',

    'recent_articles',

    'promo_image_large',

    'lead_in'
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

    my $leadins_per = $element->child('leadins_per_page')->data || 10;
    my $lead_in_count = $element->match('//lead_in/') +
      $element->match('//external_lead_in');
    my $page_count = int($lead_in_count / $leadins_per +
      ($lead_in_count % $leadins_per != 0 ? 1 : 0));

    my @page_urls;
    for (1..$page_count) {
        my $count = @page_urls;
        push @page_urls, $self->_build_page_url(page => $count,
                                                publisher => $publisher);
    }

    my $count = my $new_page = 0;
    my $page_number = 1;
    my ($element_loop, $page_loop);

    my @children = $element->children;
    for my $i(0..$#children) {
        $_ = $children[$i];
        my $template_args;
        my $name = $_->name;

        $count++ if $name =~ /lead_in/i;

        push @$element_loop, {"is_$name" => 1,
                              $name => $_->publish(publisher => $publisher)};

        if ($count == $leadins_per || $i == $#children) {
            $template_args =
              $self->_build_pagination_vars(page_list => \@page_urls,
                                            page_num => $page_number++);
            push @$page_loop, {element_loop => [@$element_loop],
                               %$template_args};

            $element_loop = undef;
            $count = 0;
        }

    }

    $tmpl->param(page_loop => $page_loop);

    $self->SUPER::fill_template(%args);
}


1;
