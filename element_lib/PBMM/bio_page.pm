package PBMM::bio_page;
use strict;
use warnings;

=head1 NAME

PBMM::page

=head1 DESCRIPTION

PBMM bio page class.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'bio_page',
                min  => 1,
                pageable => 1,
                children => 
                [ 
                Krang::ElementClass::CheckBox->new(    name => 'link_to_top_of_page',
                                            default => 1,
                                            min => 1,
                                            max => 1,
                                            allow_delete => 0,
                                            reorderable => 0 ),
                 PBMM::custom_search->new(max => 1),
                 Krang::ElementClass::Text->new(name => "large_header"),
                 Krang::ElementClass::Text->new(name => "small_header"),
                 Krang::ElementClass::Textarea->new( display_name => "Person's Bio", name => "paragraph",
                                                    bulk_edit => 1),
                 Krang::ElementClass::Text->new(display_name = "Person's Name", 
, name => "name", max => 1),    
                  Krang::ElementClass::Text->new(display_name => "Person's Title", name => "person_title", max => 1),
                 Krang::ElementClass::Text->new(name => "page_title", max => 1),
                 Krang::ElementClass::Text->new(display_name => "Person's Email", name => "email", max => 1),
                 PBMM::image->new( max => 1 ),
                 PBMM::image->new( name => 'logo', max => 1 ),
                 'document',
                PBMM::table_of_contents->new(),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

1;
