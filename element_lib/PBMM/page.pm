package PBMM::page;
use strict;
use warnings;

=head1 NAME

PBMM::page

=head1 DESCRIPTION

PBMM article page class.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'page',
                min  => 1,
                pageable => 1,
                children => 
                [ 
                 Krang::ElementClass::Text->new(name => "large_header"),
                 Krang::ElementClass::Text->new(name => "small_header"),
                 Krang::ElementClass::Textarea->new(name => "paragraph",
                                                    bulk_edit => 1),
                 Default::image->new(),
                 'document',
                Default::empty->new(name => "custom_search", max => 1),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;

    my $tmpl      = $args{tmpl};
    my $element   = $args{element};
    my $publisher = $args{publisher};
    
    my $parent = $element->parent();

    my $rel_articles = $parent->child('article_related_link_box') || '';

    if ($rel_articles) {
        $tmpl->param( article_related_link_box => $rel_articles->publish(publisher => $publisher) );
    }

    $self->SUPER::fill_template( %args );
}

1;
