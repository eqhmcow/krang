package PBMM::bio_article;
use strict;
use warnings;
use base 'Krang::ElementClass::TopLevel';
use PBMM::meta;

sub new {
    my $pkg = shift;

    my @fixed = (min  => 1,
                 max  => 1,
                 reorderable => 0,
                 allow_delete => 0);

    my %args = 
      ( 
       name => 'bio_article',
       children => 
       [
        PBMM::meta->new(),
        Krang::ElementClass::Text->new(name => 'issue_id',
                                       max  => 1),
        Krang::ElementClass::CheckBox->new(name => 'enhanced_content',
                                           @fixed),
        Krang::ElementClass::Text->new(name => 'promo_title',
                                       @fixed),
        Krang::ElementClass::Textarea->new(name => 'promo_teaser',
                                           @fixed),
        Krang::ElementClass::Textarea->new(name => 'deck',
                                           @fixed),
        Krang::ElementClass::MediaLink->new(name => 'promo_image_small',
                                            max  => 1),
        Krang::ElementClass::MediaLink->new(name => 'promo_image_large',
                                            max  => 1),
        Krang::ElementClass::Text->new(name         => 'icopywrite_link',
                                       display_name => 'iCopywrite Link',
                                       max          => 1),        
        'bio_page',

       ]);
    return $pkg->SUPER::new(%args);
}

1;
