package PBMM::auto_navigation;
use strict;
use warnings;

=head1 NAME

PBMM::auto_navigation

=head1 DESCRIPTION

PBMM auto_navigation element class for Krang.
Generates a loop of top level categories (alpha, with 'Home' on top),
and links to them.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'auto_navigation',
                @_);
   return $pkg->SUPER::new(%args);
}

sub input_form {
    return '';
}


sub fill_template {
    my ($self, %args) = @_;
                                                                                
    my $tmpl      = $args{tmpl};
    my $cat   = $args{element}->object;
    my $publisher = $args{publisher};

    my $parent = $args{element}->parent();
    
    $tmpl->param( "is_".$parent->name => 1);

    my @category_loop;

    my $top_cat = $cat; 

    # get true top level category for site
    while ( $top_cat->parent ) {
        $top_cat = $top_cat->parent;
    }
    
    push(@category_loop, { name => 'Home', url => $top_cat->url });

    foreach my $child ($top_cat->children(order_by => 'dir')) {
        push(@category_loop, { name => $child->element->child('display_name')->data, url => $child->url });
    } 

    $tmpl->param( category_loop => \@category_loop );
}

1;
