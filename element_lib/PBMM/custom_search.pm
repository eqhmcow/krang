package PBMM::custom_search;
use strict;
use warnings;

=head1 NAME

PBMM::custom_search

=head1 DESCRIPTION

PBMM custoM_search element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'custom_search',
                children => 
                [
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
