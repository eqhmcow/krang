package Default::cover;
use strict;
use warnings;

use base 'Krang::ElementClass::Cover';

sub new {
   my $pkg = shift;
   my %args = ( name => 'cover',
                children => [
                    Krang::ElementClass::Text->new( name => 'metadata_title',
                                                        display_name => 'Metadata Title', 
                                                         min => 1,
                                                         max => 1,
                                                         reorderable => 0,
                                                         allow_delete => 0,
                                                        ),
                    Krang::ElementClass::Textarea->new(name => 'metadata_description',
                                                        display_name => 'Metadata Description',
                                                        min => 1,
                                                        max => 1,
                                                        reorderable => 0,
                                                        allow_delete => 0,
                                                        ),
                    Default::fancy_keyword->new( name => 'metadata_keywords',
                                        display_name => 'Metadata Keywords',
                                        min => 1,
                                        max => 1,
                                        reorderable => 0,
                                        allow_delete => 0,
                                                        ),
                    Krang::ElementClass::Text->new(name => 'promo_title',
                                                        display_name => 'Promo Title',
                                                        min => 1,
                                                        max => 1,
                                                        required => 1,
                                                        reorderable => 0,
                                                        allow_delete => 0,
                                                        ),
                    Krang::ElementClass::Textarea->new(name => 'promo_teaser',
                                                        display_name => 'Promo Teaser',
                                                        min => 1,
                                                        max => 1,
                                                        reorderable => 0,
                                                        allow_delete => 0,
                                                        ),
                  Default::promo_image->new(name => 'promo_image_large'),
                  Default::promo_image->new(name => 'promo_image_small'),
                  Default::cover_page->new()
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

# setup cover to republish hourly by default
sub default_schedules {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    my $story = $element->story;
    my $sched = Krang::Schedule->new(object_type => 'story',
                                     object_id   => $story->story_id,
                                     action      => 'publish',
                                     repeat      => 'hourly',
                                     minute      => 0);
    croak("Unable to create schedule!") unless $sched;
    return ($sched);
}

1;
