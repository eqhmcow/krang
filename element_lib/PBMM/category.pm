package PBMM::category;
use strict;
use warnings;

use PBMM::category_ocs;
use Carp qw(croak);

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
                             PBMM::category_ocs->new(),
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
                    Krang::ElementClass::ListGroup->new( name     => "related_properties",
                                                        list_group => 'Properties',
                                                        multiple => 1,
                                                        size     => 5,
                                                        max => 1 ),
                    PBMM::top_cat_column->new(),
                    PBMM::left_cat_column->new(),
                    PBMM::right_cat_column->new(),
                    Default::empty->new(    name => 'footer',
                                            max => 1
                                            )
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

    my @inheritable = qw( related_properties footer left_cat_column right_cat_column top_cat_column primary_css secondary_css );
   
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

# export to OCS on save
sub save_hook {
    my $self = shift;
    my %arg = @_;
    my $element = $arg{element};
    my ($category_ocs) = $element->match('/category_ocs[0]');
    croak("Cannot find category_ocs child for article.")
      unless $category_ocs;
    $category_ocs->class->ocs_export_category(element => $category_ocs);
}

# remove from OCS on delete
sub delete_hook {
    my $self = shift;
    my %arg = @_;
    my $element = $arg{element};
    my ($category_ocs) = $element->match('/category_ocs[0]');
    croak("Cannot find category_ocs child for article.")
      unless $category_ocs;
    $category_ocs->class->ocs_unexport_category(element => $category_ocs);
}

1;

   
