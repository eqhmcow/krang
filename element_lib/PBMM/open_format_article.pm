package PBMM::open_format_article;
use strict;
use warnings;
use PBMM::meta;
use PBMM::promo;
                                                                           

use base 'Krang::ElementClass::TopLevel';

sub new {
   my $pkg = shift;
   my @fixed = (min  => 1,
                 max  => 1,
                 reorderable => 0,
                 allow_delete => 0);

   my %args = ( name => 'open_format_article',
                children => [
                    PBMM::meta->new(),
                    Krang::ElementClass::Text->new(name => 'issue_id',
                                       max  => 1),
                    Krang::ElementClass::CheckBox->new(name => 'enhanced_content',
                                           @fixed),
                    PBMM::promo->new(),
                    Krang::ElementClass::Textarea->new(   name => 'open_format_page',
                                                        display_name => 'Open Format Page',
                                                        pageable => 1,
                                                        rows => 10,
                                                        cols => 50,
                                                        min => 1 )
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

1;
