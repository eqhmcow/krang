package Tutorial::cover_story;

use strict;
use warnings;

=head1 NAME

Tutorial::cover_story

=head1 DESCRIPTION

cover_story element class for Tutorial.  It has the following sub-elements:

headline, paragraph, story_link, image_link

=cut

use base 'Krang::ElementClass::Cover';

sub new {

    my $pkg  = shift;

    my %args = ( name     => 'cover_story',
                 children => [
                              Krang::ElementClass::Text->new(name => 'headline',
                                                             allow_delete => 0,
                                                             size => 40,
                                                             min => 1,
                                                             max => 1,
                                                             reorderable => 0,
                                                             required => 1),

                              Krang::ElementClass::Textarea->new(name => 'paragraph'),

                              Krang::ElementClass::StoryLink->new(name => 'story_link'),

                              Krang::ElementClass::MediaLink->new(name => 'media_link'),

                             ],
                 @_);
    return $pkg->SUPER::new(%args);
}

1;
