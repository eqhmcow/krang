package PBMM::top_cat_column;
use strict;
use warnings;

=head1 NAME

PBMM::top_cat_column

=head1 DESCRIPTION

PBMM top category column element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;

   my @fixed = (min  => 1,
                 max  => 1,
                 reorderable => 0,
                 allow_delete => 0);
 
   my %args = ( name => 'top_cat_column',
                max => 1,
                children => 
                [
                 PBMM::search_type->new(
                                        max  => 1,
                                        ),
                 PBMM::ad_module->new(),
                 PBMM::auto_navigation->new(
                                        max => 1 ),
                 PBMM::html_include->new(),
                 PBMM::cat_paragraph->new(),
                 Default::lead_in->new(),
                 PBMM::image->new(),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;
                                                                                
    my $tmpl      = $args{tmpl};
    my $element   = $args{element};

    my @ad_m =  grep { $_->name() eq 'ad_module' } $element->children();

    my %a_count;
    
    foreach my $ad_m (@ad_m) {
        $a_count{$ad_m->child('size')->data.'_count'}++;
    }

    $tmpl->param( \%a_count );

    $self->SUPER::fill_template( %args );
}

1;
