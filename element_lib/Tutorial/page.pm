package Tutorial::page;

use strict;
use warnings;

=head1 NAME

Tutorial::page

=head1 DESCRIPTION

the page element class for Tutorial.

It will be used by basic_story - the multi-page story type.

page has the following children:

page_header, paragraph, story_link, image_link

=cut

use base 'Krang::ElementClass';

sub new {
    my $pkg  = shift;
    my %args = ( name => 'page',
                 min  => 1,
                 pageable => 1,
                 children => [
                              Krang::ElementClass::Text->new(name => 'page_header',
                                                             min  => 1,
                                                             max  => 1,
                                                             reorderable  => 0,
                                                             allow_delete => 0
                                                            ),
                              Krang::ElementClass::Textarea->new(name => 'paragraph',
                                                                 min  => 1
                                                                ),

                              Krang::ElementClass::StoryLink->new(name => 'story_link'),
                              Krang::ElementClass::MediaLink->new(name => 'image_link')
                             ],
                 @_
               );

    return $pkg->SUPER::new(%args);

}

1;
