package PBMM::bio_article;
use strict;
use warnings;
use base 'Krang::ElementClass::TopLevel';
use PBMM::meta;
use PBMM::promo;
use PBMM::story_ocs;

use PBMM::ocs_hooks qw(_publish delete_hook);

# wrap ocs_hooks::_publish since SUPER doesn't work in exported methods
sub publish {
    my $self = shift;
    
    return $self->_publish(@_) . $self->SUPER::publish(@_);
}

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
        PBMM::story_ocs->new(),
        Krang::ElementClass::Text->new(name => 'issue_id',
                                       max  => 1),
        Krang::ElementClass::CheckBox->new(name => 'enhanced_content',
                                           @fixed),
        Krang::ElementClass::Textarea->new(name => 'deck',
                                           @fixed),
        PBMM::promo->new(),
        Krang::ElementClass::Text->new(name         => 'icopywrite_link',
                                       display_name => 'iCopywrite Link',
                                       max          => 1),     
        'bio_page',

       ]);
    return $pkg->SUPER::new(%args);
}

1;
