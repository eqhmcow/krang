package Default::cover_page;
use strict;
use warnings;

=head1 NAME

Default::cover_page

=head1 DESCRIPTION

Default cover  page element class for Krang. 

=cut

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'cover_page',
                min  => 1,
                pageable => 1,
                children => 
                [ 
                 pkg('ElementClass::Text')->new(name         => "section_header" ),
                 pkg('ElementClass::Text')->new(name         => "large_header" ),
                 pkg('ElementClass::Textarea')->new(name => "paragraph",
                                                    required => 1,
                                                    bulk_edit => 1,
                                                   ),
                 pkg('ElementClass::MediaLink')->new(name => "header_image" ),
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
