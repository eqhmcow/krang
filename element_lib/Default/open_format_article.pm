package Default::open_format_article;
use strict;
use warnings;

use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'open_format_article',
                children => [
                    Krang::ElementClass::Text->new( name => 'metadata_title',
                                                        display_name => 'Metadata Title', 
                                                         min => 1,
                                                         max => 1,
                                                         reorderable => 0,
                                                         allow_delete => 0,
                                                        ),
                    Krang::ElementClass::Textarea->new(name => 'metadata_description',
                                                        display_name => 'Metadata Description',
                                                        min => 1,
                                                        max => 1,
                                                        reorderable => 0,
                                                        allow_delete => 0,
                                                        ),
                    Default::fancy_keyword->new( name => 'metadata_keywords',
                                        display_name => 'Metadata Keywords',
                                        min => 1,
                                        max => 1,
                                        reorderable => 0,
                                        allow_delete => 0,
                                                        ),
                    Krang::ElementClass::Text->new(name => 'promo_title',
                                                        display_name => 'Promo Title',
                                                        min => 1,
                                                        max => 1,
                                                        required => 1,
                                                        reorderable => 0,
                                                        allow_delete => 0,
                                                        ),
                    Krang::ElementClass::Textarea->new(name => 'promo_teaser',
                                                        display_name => 'Promo Teaser',
                                                        min => 1,
                                                        max => 1,
                                                        reorderable => 0,
                                                        allow_delete => 0,
                                                        ),
                  Default::promo_image->new(name => 'promo_image_large'),
                  Default::promo_image->new(name => 'promo_image_small'),
                  Krang::ElementClass::Textarea->new(   name => 'open_format_page',
                                                        display_name => 'Open Format Page',
                                                        rows => 10,
                                                        cols => 50,
                                                        min => 1 )
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

1;
