package Default::cover_page;
use strict;
use warnings;

=head1 NAME

Default::cover_page

=head1 DESCRIPTION

Default cover  page element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'cover_page',
                min  => 1,
                pageable => 1,
                children => 
                [ 
                 Krang::ElementClass::Text->new(name         => "section_header" ),
                 Krang::ElementClass::Text->new(name         => "large_header" ),
                 Krang::ElementClass::Textarea->new(name => "paragraph",
                                                    required => 1,
                                                    bulk_edit => 1,
                                                   ),
                 Krang::ElementClass::MediaLink->new(name => "header_image" ),
                 Default::lead_in->new(),
                 Default::external_lead_in->new(),
                 Default::image->new(),
                 Default::empty->new( name => 'horizontal_line' ),
                 Default::double_cover_column->new(   name => "double_column" ),

                ],
                @_);
   return $pkg->SUPER::new(%args);
}


1;
