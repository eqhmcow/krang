package TestParent1::cover;
use strict;
use warnings;

use base 'Krang::ElementClass::Cover';

sub new {
   my $pkg = shift;
   my %args = ( name => 'cover',
                children => [
                  Krang::ElementClass::Textarea->new(name => 'header',
                                                     min => 1,
                                                     max => 1,
                                                     reorderable => 0,
                                                     allow_delete => 0,
                                                    ),
                  Krang::ElementClass::StoryLink->new(name => 'leadin',
                                                      display_name => 
                                                      'Lead-In',
                                                     ),
                  Krang::ElementClass::MediaLink->new(name => 'photo'),
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
