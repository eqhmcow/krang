package PBMM::article;
use strict;
use warnings;
use base 'Krang::ElementClass::TopLevel';
use PBMM::meta;
use PBMM::promo;
use OCS::Exporter;
use Time::Piece;
use Carp qw(croak);
use Krang::Log qw(debug);

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
       name => 'article',
       children => 
       [
        Krang::ElementClass::Text->new(name => 'issue_id',
                                       max  => 1),
        Krang::ElementClass::Text->new(name => 'article_id',
                                       max  => 1),
        PBMM::story_ocs->new(),
        PBMM::meta->new(),
        Krang::ElementClass::Text->new(name => 'source',
                                       max  => 1),
        Krang::ElementClass::Textarea->new(name => 'byline',
                                           max => 1),
        Krang::ElementClass::CheckBox->new(name => 'enhanced_content',
                                           @fixed),
        Krang::ElementClass::Textarea->new(name => 'deck',
                                           @fixed),
        Krang::ElementClass::CheckBox->new(    name => 'link_to_top_of_page',
                                            default => 1,
                                            min => 1,
                                            max => 1,
                                            allow_delete => 0,
                                            reorderable => 0 ),
        PBMM::promo->new(),
        Krang::ElementClass::Text->new(name         => 'icopyright_link',
                                       display_name => 'iCopyright Link',
                                       max          => 1),       
        PBMM::custom_targeting->new(max => 1),
        'page',

       ]);
    return $pkg->SUPER::new(%args);
}

1;
