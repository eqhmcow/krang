package PBMM::category;
use strict;
use warnings;

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
                    PBMM::top_cat_column->new(allow_delete => 0),
                    PBMM::left_cat_column->new(allow_delete => 0),
                    PBMM::right_cat_column->new(allow_delete => 0),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;
    my $story   = $args{publisher}->story;
    my $tmpl      = $args{tmpl};
    $tmpl->param( title =>  $story->title );
    $tmpl->param( meta_description =>  $story->element->child('meta_description')->data );
    my $keywords = $story->element->child('meta_keywords')->data;
    my @keys;
    foreach my $kw (@$keywords) {
        push (@keys, {meta_keyword => $kw});
    }
    $tmpl->param( meta_keyword_loop => \@keys );
    $self->SUPER::fill_template( %args ); 
}

1;

   
