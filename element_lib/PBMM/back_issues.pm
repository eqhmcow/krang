package PBMM::back_issues;
use strict;
use warnings;

=head1 NAME
                                                                                
PBMM::search_type
                                                                                
=head1 DESCRIPTION
                                                                                
PBMM back_issue element class for Krang. Outputs loop of issue covers
                                                                                
=cut

use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'back_issues',
                children =>
                [
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;
                                                                                    my $tmpl      = $args{tmpl};
    my $story   = $args{element}->object;
    my $publisher = $args{publisher};

    my @s = Krang::Story->find( class => 'issue_cover', published => '1', order_by => 'cover_date', order_desc => 1 );

    my @story_loop;
    my $story_count = 0;

    foreach my $s (@s) {
        next if ($s->story_id eq $story->story_id);

        my $ptitle = $s->element->child('promo_title')->data || $s->title;
                                                                           
        push (@story_loop, {story_count => ++$story_count, 
                            url => 'http://'.($publisher->is_preview ? $s->preview_url : $s->url).'/', 
                            promo_title => $ptitle,
                            story_title => $s->title,
                            cover_date => $s->cover_date->strftime('%b %e, %Y') } ); 
    } 

    $tmpl->param( story_loop => \@story_loop );

    $self->SUPER::fill_template( %args );
}
1;
