package PBMM::open_article;
use strict;
use warnings;
use PBMM::meta;
use PBMM::promo;
use PBMM::story_ocs;

use base 'Krang::ElementClass::TopLevel';

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

   my %args = ( name => 'open_article',
                children => [
                    Krang::ElementClass::Text->new(name => 'issue_id',
                                       max  => 1),
                    Krang::ElementClass::Text->new(name => 'article_id',
                                       max  => 1),
                             PBMM::story_ocs->new(),
                    Krang::ElementClass::Textarea->new(name => 'byline',
                                           max => 1),
                    Krang::ElementClass::Textarea->new(name => 'deck',
                                           @fixed),
                    Krang::ElementClass::CheckBox->new(name => 'enhanced_content',
                                           @fixed),
                    Krang::ElementClass::CheckBox->new(    name => 'link_to_top_of_page',
                                            default => 1,
                                            min => 1,
                                            max => 1,
                                            allow_delete => 0,
                                            reorderable => 0 ),
                    PBMM::meta->new(),
                    PBMM::promo->new(),
                    PBMM::custom_search->new(max => 1),
                    Krang::ElementClass::Textarea->new(   name => 'body',
                                                        display_name => 'Page Content',
                                                        pageable => 1,
                                                        rows => 10,
                                                        cols => 38,
                                                        min => 1 ),
                    PBMM::table_of_contents->new(),
                    PBMM::custom_targeting->new(max =>1)
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

1;
