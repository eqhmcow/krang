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
                     Krang::ElementClass::Text->new( name => 'title',
                                                         min => 1,
                                                         max => 1,
                                                         reorderable => 0,
                                                         allow_delete => 0,
                                                        ),
                    Krang::ElementClass::CheckBox->new( name => 'colored_background',
                                                        min => 1,
                                                         max => 1,
                                                         reorderable => 0,
                                                         allow_delete => 0,
                                                        ),
 
                ],
                @_);
   return $pkg->SUPER::new(%args);
}


1;
