package PBMM::open_article;
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

   my %args = ( name => 'open_article',
                children => [
                    Krang::ElementClass::Text->new(name => 'issue_id',
                                       max  => 1),
                    Krang::ElementClass::Text->new(name => 'article_id',
                                       max  => 1),
                    Krang::ElementClass::Textarea->new(name => 'byline',
                                           max => 1),

                    Krang::ElementClass::CheckBox->new(name => 'enhanced_content',
                                           @fixed),
                    PBMM::meta->new(),
                    PBMM::promo->new(),
                     Krang::ElementClass::PopupMenu->new(name => "search_type",
                                                     @fixed,
                                                     values => [ "keyword",                                                                 "topic",
                                                                 "multisite",
                                                                 "custom"],                                                     default => "keyword"),
                    Krang::ElementClass::Textarea->new(   name => 'content',
                                                        display_name => 'Content',
                                                        pageable => 1,
                                                        rows => 10,
                                                        cols => 50,
                                                        min => 1 )
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

1;
