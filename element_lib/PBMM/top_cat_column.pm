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
                min  => 1,
                max => 1,
                reorderable => 0,
                children => 
                [
                 PBMM::search_type->new(min  => 1,
                                        max  => 1,
                                        allow_delete => 0),
                 Krang::ElementClass::Text->new(name         => "ad_module",
                                                min => 1,
                                                ),
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


1;
