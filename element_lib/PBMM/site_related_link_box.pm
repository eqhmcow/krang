package PBMM::site_related_link_box;
use strict;
use warnings;

=head1 NAME

PBMM::site_related_link_box

=head1 DESCRIPTION

PBMM article_related_link_box element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'site_related_link_box',
                children => 
                [
                     Krang::ElementClass::Text->new(name         => "number_to_display",
                                                    min => 1,
                                                        max => 1,
                                                        allow_delete => 1,
                                                        reorderable => 0,
                                                        required => 1,
                                                        default => '10' ),
                                                                                
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


1;
