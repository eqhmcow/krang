package PBMM::left_cat_column;
use strict;
use warnings;

=head1 NAME

PBMM::left_cat_column

=head1 DESCRIPTION

PBMM left category column element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;

    my @fixed = (min  => 1,
                 max  => 1,
                 reorderable => 0,
                 allow_delete => 0);

   my %args = ( name => 'left_cat_column',
                min  => 1,
                max => 1,
                reorderable => 0,
                children => 
                [ 
                 Krang::ElementClass::PopupMenu->new(name => "search_type",
                                                     @fixed,
                                                     values => [ "keyword",
                                                                 "topic",
                                                                 "multisite",
                                                                 "custom"],
                                                     default => "keyword"),
                Krang::ElementClass::MediaLink->new(name => "navigation_include"),
               
                PBMM::site_related_link_box->new( max => 1), 
                Default::empty->new(name => "table_of_contents", max => 1 ), 
                 Krang::ElementClass::Text->new(name         => "ad_module",
                                                min => 1,
                                                allow_delete => 0),
                 Krang::ElementClass::MediaLink->new(name => "html_include",
                                                     ),
                 Krang::ElementClass::Text->new(name         => "small_header" ),
                 Krang::ElementClass::Text->new(name         => "large_header" ),
                 Krang::ElementClass::Textarea->new(name => "paragraph",
                                                    required => 1,
                                                    bulk_edit => 1,
                                                   ),
                 Default::lead_in->new(),
                 PBMM::image->new(),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}


1;
