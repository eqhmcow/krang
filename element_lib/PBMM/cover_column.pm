package PBMM::cover_column;
use strict;
use warnings;

=head1 NAME

Default::cover_column

=head1 DESCRIPTION

Default cover_column element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'cover_column',
                min  => 1,
                children => 
                [ 
                 Krang::ElementClass::Text->new(name         => "small_header" ),
                 Krang::ElementClass::Text->new(name         => "large_header" ),
                 Krang::ElementClass::Textarea->new(name => "paragraph",
                                                    required => 1,
                                                    bulk_edit => 1,
                                                   ),
                 Default::lead_in->new(),
                 PBMM::external_lead_in->new(),
                 PBMM::image->new(),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}


1;
