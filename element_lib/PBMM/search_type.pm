package PBMM::search_type;
use strict;
use warnings;
use Krang::List;
use Krang::ListGroup;
use Krang::ListItem;

=head1 NAME

PBMM::search_type

=head1 DESCRIPTION

PBMM search_type element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'search_type',
                children => 
                [
                    Krang::ElementClass::PopupMenu->new(name => "type",
                                                     values => [ "keyword",
                                                                 "topic",
                                                                 "multisite" ],
                                                     default => "keyword",
                                                    min => 1,
                                                    max => 1,
                                                    allow_delete => 1,
                                                    reorderable => 0),
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

sub input_form {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    return $element->child('type')->data;
}

sub fill_template {
    my ($self, %args) = @_;
    my $tmpl      = $args{tmpl};
    my $cat   = $args{element}->object;

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


    if (not $cat->element->child('related_properties')) {
        my $found = 0;
        while (not $found) {
            if($cat->parent) {
                $cat = $cat->parent;
                if ($cat->element->child('related_properties')) {
                    $found = 1;
                    my $keywords = $cat->element->child('related_properties')->data;
                    my @k;
                    foreach my $kw (@$keywords) {
                        push (@k, {display_name => (Krang::ListItem->find(list_item_id => $kw))[0]->data, list_item_id => $kw});
                    }
                    $tmpl->param( related_properties_loop => [@k] );
                }
            } else {
                last;
            }
        }
    } else {
        my $keywords = $cat->element->child('related_properties')->data;
        my @k;
        foreach my $kw (@$keywords) {
            push (@k, {display_name => (Krang::ListItem->find(list_item_id => $kw))[0]->data, list_item_id => $kw});
        }
        $tmpl->param( related_properties_loop => [@k] );
    }

    $self->SUPER::fill_template( %args );
}

1;
