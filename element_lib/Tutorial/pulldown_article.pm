package Tutorial::pulldown_article;

use strict;
use warnings;

=head1 NAME

Tutorial::pulldown_article - article type that makes use of Krang lists.


=head1 DESCRIPTION

Tutorial::pulldown_article is used to demonstrate how lists work in Krang.

=cut

use base 'Krang::ElementClass::TopLevel';

sub new {
    my $pkg  = shift;
    my %args = (
                name => 'pulldown_article',
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

                             Krang::ElementClass::ListGroup->new(name => 'segments',
                                                                 list_group => 'Segments',
                                                                 multiple => 1,
                                                                 min => 1,
                                                                 max => 1,
                                                                ),

                             Krang::ElementClass::ListGroup->new(name => 'car_selector',
                                                                 list_group => 'Cars',
                                                                 multiple => 0,
                                                                 min => 1,
                                                                 max => 1,
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
