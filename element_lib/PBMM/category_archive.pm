package PBMM::category_archive;
use strict;
use warnings;
use PBMM::meta;
use PBMM::promo;

use base 'Krang::ElementClass::TopLevel';

sub new {
   my $pkg = shift;
   my @fixed = (min  => 1,
                 max  => 1,
                 reorderable => 0,
                 allow_delete => 0);

   my %args = ( name => 'category_archive',
                children =>
                [
                Krang::ElementClass::CheckBox->new(name => 'enhanced_content',
                                           @fixed),
                Krang::ElementClass::CheckBox->new(name => 'automatic_leadins',
                                                    default => 1,
                                           @fixed),
                Krang::ElementClass::Text->new( name => 'leadins_per_page',
                                                default => 25,
                                       @fixed),
                PBMM::meta->new(),
                PBMM::promo->new(),
                Krang::ElementClass::PopupMenu->new(name => "search_type",
                                                     @fixed,
                                                     values => [ "keyword",
                                                                 "topic",
                                                                 "multisite",
                                                                 "custom"],
                                                     default => "keyword"),
                Krang::ElementClass::Text->new(name => "large_header"),
                Krang::ElementClass::Text->new(name => "small_header"),
                Krang::ElementClass::Textarea->new(name => "paragraph",
                                                    bulk_edit => 1),
                Default::image->new(),
                Default::lead_in->new(), 
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;
                                                                                
    my $tmpl      = $args{tmpl};
    my $story   = $args{element}->object;
    my $publisher = $args{publisher};

    # get stories in this category
    my @s = Krang::Story->find( category_id => $story->category->category_id, published => '1', order_by => 'cover_date', order_desc => 1 );

    my @story_loop;
    my @page_loop;
    my $story_count = 0;

    foreach my $s (@s) {
        push (@story_loop, {page_story_count => ++$story_count, url => 'http://'.($publisher->is_preview ? $s->preview_url : $s->url).'/', 
                            title => $s->title,
                            cover_date => $s->cover_date->strftime('%b %e, %Y') } ) if ($s->story_id ne $story->story_id);

        if ($story_count == 10) {
            push (@page_loop, { story_loop => [@story_loop] } );
            @story_loop = ();
            $story_count = 0;
        }
    } 

    if ($story_count) {
        push (@page_loop, { story_loop => [@story_loop] } );
    }

    $tmpl->param( page_loop => \@page_loop );
}
1;
