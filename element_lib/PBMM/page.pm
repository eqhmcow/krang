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
                 PBMM::image->new(),
                 'document',
                PBMM::custom_search->new(max => 1),
                PBMM::page_ad_module->new(display_name => 'Ad Module' ),
                PBMM::table_of_contents->new(),

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

    $tmpl->param( icopyright_link => $parent->child('icopyright_link')->data ) if $parent->child('icopyright_link');

    $self->SUPER::fill_template( %args );
}

1;
