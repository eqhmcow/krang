package PBMM::cat_paragraph;
use strict;
use warnings;

=head1 NAME

PBMM::cat_paragraph

=head1 DESCRIPTION

PBMM category paragraph element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'cat_paragraph',
                display_name => 'Paragraph',
                children => 
                [
                    Krang::ElementClass::Textarea->new(name => "text",
                                                        min => 1,
                                                        max => 1,
                                                        allow_delete => 1,
                                                        reorderable => 0
                                                     ),
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
