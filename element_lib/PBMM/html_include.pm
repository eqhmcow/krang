package PBMM::html_include;
use strict;
use warnings;

=head1 NAME

Default::html_include

=head1 DESCRIPTION

PBMM html_include element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'html_include',
                display_name => 'HTML Include',
                children => 
                [
                    Krang::ElementClass::MediaLink->new(name => "file",
                                                        min => 1,
                                                        max => 1,
                                                        required => 1,
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
