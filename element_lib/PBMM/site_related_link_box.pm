package PBMM::site_related_link_box;
use strict;
use warnings;

=head1 NAME

PBMM::site_related_link_box

=head1 DESCRIPTION

PBMM article_related_link_box element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'site_related_link_box',
                children => 
                [
                     Krang::ElementClass::Text->new(name         => "number_to_display",
                                                    min => 1,
                                                        max => 1,
                                                        allow_delete => 1,
                                                        reorderable => 0,
                                                        required => 1,
                                                        default => '10' ),
                                                                                
                    Krang::ElementClass::CheckBox->new(name => 'table_background',
                                                       min => 1,
                                                        max => 1,
                                                        allow_delete => 1,
                                                        reorderable => 0,
                                                        default => 0
                                                     ),
                     Krang::ElementClass::Text->new(name         => "table_title",
                                                    min => 1,
                                                        max => 1,
                                                        allow_delete => 1,
                                                        reorderable => 0 ),
 
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;
                                                                                
    my $tmpl      = $args{tmpl};
    my $cat   = $args{element}->object;
    my $story   = $args{publisher}->story;
   
    my $keywords = $story->element->child('meta_keywords')->data;
 
    # note the following searches thru all articles for matching meta
    # keywords. in the future this should be indexed, but fix in 
    # Krang::ElementClass is needed first.

    my $top_cat = $cat;
                                                                                
    # get true top level category for site
    while ( $top_cat->parent ) {
        $top_cat = $top_cat->parent;
    }

    my @stories = Krang::Story->find( site_id => $top_cat->site->site_id, class => 'article', published => 1 ); 

    my @article_loop;

    foreach my $s (@stories) {
        my $matched = 0;

        next if ($s->story_id eq $story->story_id);
        foreach my $key (@$keywords) {
            my $ks = $s->element->child('meta_keywords')->data;
            foreach my $k (@$ks) {
                if ($k eq $key) {
                    my %ps;
                    $ps{title} = $s->element->child('promo_title')->data || $s->title;
                    $ps{url} = $s->url;
                    $ps{teaser} = $s->element->child('promo_teaser')->data if $s->element->child('promo_teaser')->data;
                    push (@article_loop, \%ps );
                    $matched = 1;
                    last;
                }
            }
            last if $matched;
        }
    }

    $tmpl->param(article_loop => \@article_loop);
    $self->SUPER::fill_template( %args );
}

1;
