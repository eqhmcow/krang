package Default::category_archive;
use strict;
use warnings;

use base 'Krang::ElementClass';

#use Krang::Story;

sub new {
   my $pkg = shift;
   my %args = ( name => 'category_archive',
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;
                                                                                
    my $tmpl      = $args{tmpl};
    my $story   = $args{element}->object;
    my $publisher = $args{publisher};

    # get stories in this category
    my @s = Krang::Story->find( category_id => $story->category->category_id, published => '1' );

    my @story_loop = ();

    foreach my $s (@s) {
        push (@story_loop, {url => 'http://'.$s->url.'/', 
                            title => $s->title } ) if ($s->story_id ne $story->story_id);
    } 

    $tmpl->param( story_loop => \@story_loop );
}
1;
