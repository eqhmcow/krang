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
                                                   values => [  "468x60",
                                                                "125x125",
                                                                "120x600",
                                                                "728x90"    ],
                                                   default => "468x60"
                                                           ),
                ],
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
    my $story   = $args{publisher}->story;
   
    $tmpl->param( slug => $story->slug );
 
    my $parent = $args{element}->parent();
    
    $tmpl->param( "is_".$parent->name => 1);
   
    my @split_site = split('.', $cat->site->url);
 
    $tmpl->param( site => $split_site[1] );
    
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
