package Default::category_archive;
use strict;
use warnings;

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'ElementClass::TopLevel';

sub new {
   my $pkg = shift;
   my %args = ( name => 'category_archive',
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;

    my $tmpl      = $args{tmpl};
    my $story     = $args{element}->object;
    my $publisher = $args{publisher};

    # get stories in this category
    my @s = pkg('Story')->find( category_id => $story->category->category_id, published => '1', order_by => 'cover_date', order_desc => 1 );

    my @story_loop;
    my @page_loop;
    my $story_count = 0;

    foreach my $s (@s) {
        if ($s->story_id ne $story->story_id) {
            push @story_loop, {
                               page_story_count => ++$story_count, 
                               url => 'http://'.($publisher->is_preview ? $s->preview_url : $s->url).'/',
                               title => $s->title,
                               cover_date => $s->cover_date->strftime('%b %e, %Y'),
                               promo_teaser => $s->element->child_data('promo_teaser'),
                              };
        }

        if ($story_count == 10) {
            push (@page_loop, { story_loop => [@story_loop] } );
            @story_loop = ();
            $story_count = 0;
        }
    } 

    if ($story_count) {
        push (@page_loop, { story_loop => [@story_loop] } );
    }

    $tmpl->param(
                 page_loop => \@page_loop,
                 title     => $story->title()
                );


}
1;
