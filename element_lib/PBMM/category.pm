package PBMM::category;
use strict;
use warnings;

=head1 NAME

PBMM::category

=head1 DESCRIPTION

PBMM category element class for Krang.  

=cut


use base 'Krang::ElementClass::TopLevel';

sub new {
   my $pkg = shift;
   my %args = ( name => 'category',
                children => [
                    Krang::ElementClass::Text->new(name => 'display_name',
                                                            allow_delete => 0,
                                                            min => 1,
                                                            max => 1,
                                                            reorderable => 0,
                                                            required => 1),
                    Krang::ElementClass::Text->new(name => 'primary_css',
                                                            max => 1,
                                                            ),
                    Krang::ElementClass::Text->new(name => 'secondary_css',
                                                            max => 1,
                                                            ),
                    PBMM::top_cat_column->new(),
                    PBMM::left_cat_column->new(),
                    PBMM::right_cat_column->new(),
                    Default::empty->new(    name => 'footer',
                                            max => 1
                                            ),
                    Default::empty->new(    name => 'link_to_top_of_page',  
                                            max => 1 )
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;
    my $story   = $args{publisher}->story;
    my $tmpl      = $args{tmpl};
    my $element = $args{element};
    my $publisher = $args{publisher};

    $tmpl->param( title =>  $story->title );
    $tmpl->param( meta_description =>  $story->element->child('meta_description')->data );
    my $keywords = $story->element->child('meta_keywords')->data;
    my @keys;
    foreach my $kw (@$keywords) {
        push (@keys, {meta_keyword => $kw});
    }
    $tmpl->param( meta_keyword_loop => \@keys );

    # handle list group info
    foreach my $list qw(meta_company_type meta_technology meta_topic meta_geography meta_source) {
        next if not $story->element->child($list);
        $keywords = $story->element->child($list)->data;
        my @k;
        foreach my $kw (@$keywords) {
            push (@k, {list_item_id => $kw});
        }
        $tmpl->param( $list.'_loop' => \@k );

    }

    my @inheritable = qw( footer left_cat_column right_cat_column top_cat_column primary_css secondary_css );
   
    foreach my $el_name (@inheritable) {
        if (not $element->child($el_name)) {
            my $category = $story->category;
            my $found = 0;
            while (not $found) {
                if ($category->parent) {
                    $category = $category->parent;
                    if( $category->element->child($el_name) ) {
                        $tmpl->param( $el_name => $category->element->child($el_name)->publish( publisher => $publisher) );
                        $found = 1; 
                    } 
                } else {
                     last;
                } 
            }
        }
    }
 
    $self->SUPER::fill_template( %args ); 
}

1;

   
