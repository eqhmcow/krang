package Default::page;
use strict;
use warnings;

=head1 NAME

Default::page

=head1 DESCRIPTION

Default page element class for Krang. 

=cut

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'page',
                min  => 1,
                pageable => 1,
                children => 
                [ 
                 pkg('ElementClass::Text')->new(name         => "section_header",
                                                display_name => 'Section Header',
                                                ),
                 pkg('ElementClass::Text')->new(name         => "large_header",
                                                display_name => 'Large Header',
                                                ),
                 pkg('ElementClass::Textarea')->new(name => "paragraph",
                                                    required => 1,
                                                    bulk_edit => 1,
                                                   ),
                 Default::image->new(),
                 Default::inset_box->new(), 
                 pkg('ElementClass::MediaLink')->new(name => "section_header_image",
                                                     display_name => 'Section Header Image'),
                 Default::empty->new( name => 'horizontal_line' )

                ],
                @_);
   return $pkg->SUPER::new(%args);
}


1;
