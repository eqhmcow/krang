package Tutorial::basic_article;

use strict;
use warnings;

=head1 NAME

Tutorial::basic_article - simple article type for the Tutorial element
library

=head1 DESCRIPTION

basic_article is a simple multi-page story type in the Tutorial
element library.

It has the following children: headline, deck, page (Tutorial::page).

=cut

use base 'Krang::ElementClass::TopLevel';

sub new {
    my $pkg  = shift;
    my %args = (
                name => 'basic_article',
                children => [
                             Krang::ElementClass::Text->new(name => 'headline',
                                                            allow_delete => 0,
                                                            size => 40,
                                                            min => 1,
                                                            max => 1,
                                                            reorderable => 0,
                                                            required => 1
                                                           ),
                             Krang::ElementClass::Textarea->new(name         => 'deck',
                                                                allow_delete => 0,
                                                                reorderable  => 0,
                                                                required     => 1,
                                                                min => 1,
                                                                max => 1
                                                               ),
                             Tutorial::page->new(name => 'article_page',
                                                 min  => 1
                                                )

                            ],
                @_
               );


    return $pkg->SUPER::new(%args);

}

1;
