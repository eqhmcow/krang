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
                children => 
                [ 
                  Default::cover_column->new(   name => "left_column",
                                                allow_delete => '0',
                                                    display_name => 'Left Column',
                                                    min => 1,
                                                    max => 1 ),
                Default::cover_column->new(   name => "right_column",
                                                allow_delete => '0',
                                                    display_name => 'Right Column',
                                                    min => 1,
                                                    max => 1 ),

                 Krang::ElementClass::Text->new(name         => "section_header",
                                                display_name => 'Section Header',
                                                ),
                 Krang::ElementClass::Text->new(name         => "large_header",
                                                display_name => 'Large Header',
                                                ),
                 Krang::ElementClass::Textarea->new(name => "paragraph",
                                                    required => 1,
                                                    bulk_edit => 1,
                                                   ),
                 Krang::ElementClass::MediaLink->new(name => "header_image",
                                                     display_name => 'Header Image'),
                 Krang::ElementClass::StoryLink->new(name => "leadin"),
                 Default::image->new(),
                 Default::external_lead_in->new(),
                 Default::horizontal_line->new( display_name => 'Horizontal Line' )

                ],
                @_);
   return $pkg->SUPER::new(%args);
}


1;
