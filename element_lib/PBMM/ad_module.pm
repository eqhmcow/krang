package PBMM::ad_module;
use strict;
use warnings;

=head1 NAME

PBMM::ad_module

=head1 DESCRIPTION

PBMM ad_module element class for Krang.
Allows users to add an ad module of chosen type, and
populated ad-related varibles based on current story and category.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'ad_module',
                children => [
                    Krang::ElementClass::PopupMenu->new(name => "size",
                                                    reorderable => '0',
                                                   min => 1,
                                                   max => 1,
                                                   allow_delete => '0',
                                                   values => [  "120x600",
                                                                "120x60",
                                                                "120x240",
                                                                "125x125",
                                                                "180x150",
                                                                "234x400",
                                                                "240x400",
                                                                "250x250",
                                                                "468x60"    ],
                                                   default => "120x600"
                                                           ),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($element) = $arg{element};
    return if not $element->child('size');
    return $element->child('size')->data;
}


sub fill_template {
    my ($self, %args) = @_;
                                                                                
    my $tmpl      = $args{tmpl};
    my $cat   = $args{element}->object;
    my $story   = $args{publisher}->story;
   
    $tmpl->param( slug => $story->slug );
 
    my $parent = $args{element}->parent();
    
    $tmpl->param( "is_".$parent->name => 1);
   
    my @split_site = split('.', $cat->site->url);
 
    $tmpl->param( site => $split_site[1] );

    if ($story->element->child('custom_targeting')) {
        $tmpl->param( keyword_1 => $story->element->child('custom_targeting')->child('keyword_1')->data );
        $tmpl->param( keyword_2 => $story->element->child('custom_targeting')->child('keyword_2')->data );
        $tmpl->param( keyword_3 => $story->element->child('custom_targeting')->child('keyword_3')->data );
        $tmpl->param( keyword_4 => $story->element->child('custom_targeting')->child('keyword_4')->data );
        $tmpl->param( keyword_5 => $story->element->child('custom_targeting')->child('keyword_5')->data );
    }
    
    if ($cat->parent) {
        if ($cat->parent->parent) {
            if ($cat->parent->parent->parent) {
                $tmpl->param( cdir => $cat->parent->parent->dir );
                $tmpl->param( scdir => $cat->parent->dir );
                $tmpl->param( sscdir => $cat->dir );

            } else {
                $tmpl->param( cdir => $cat->parent->dir );
                $tmpl->param( scdir => $cat->dir );
            }      
        } else {
            $tmpl->param( cdir => $cat->dir );
        }
    } else {
        $tmpl->param( cdir => 'home' ); 
    }

    $self->SUPER::fill_template( %args );
}

1;
