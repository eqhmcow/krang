package PBMM::article;
use strict;
use warnings;
use base 'Krang::ElementClass::TopLevel';
use PBMM::meta;
use PBMM::promo;

sub new {
    my $pkg = shift;

    my @fixed = (min  => 1,
                 max  => 1,
                 reorderable => 0,
                 allow_delete => 0);

    my %args = 
      ( 
       name => 'article',
       children => 
       [
        PBMM::meta->new(),
        Krang::ElementClass::Text->new(name => 'issue_id',
                                       max  => 1),
        Krang::ElementClass::Text->new(name => 'article_id',
                                       max  => 1),
        Krang::ElementClass::Textarea->new(name => 'byline',
                                           max => 1),
        Krang::ElementClass::CheckBox->new(name => 'enhanced_content',
                                           @fixed),
        Krang::ElementClass::Textarea->new(name => 'deck',
                                           @fixed),
        PBMM::promo->new(),
        Krang::ElementClass::Text->new(name         => 'icopywrite_link',
                                       display_name => 'iCopywrite Link',
                                       max          => 1),       
        Krang::ElementClass::PopupMenu->new(name => "search_type",
                                                     @fixed,
                                                     values => [ "keyword",
                                                                 "topic",
                                                                 "multisite",
                                                                 "custom"],
                                                     default => "keyword"),
 
        'page',

       ]);
    return $pkg->SUPER::new(%args);
}

1;
