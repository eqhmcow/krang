package PBMM::issue_cover;
use strict;
use warnings;
use PBMM::meta;
use PBMM::promo;
                                                                           
use base 'Krang::ElementClass::Cover';

sub new {
   my $pkg = shift;
   my @fixed = (min  => 1,
                 max  => 1,
                 reorderable => 0,
                 allow_delete => 0);
   my %args = ( name => 'issue_cover',
                children => [
                    PBMM::meta->new(),
                    Krang::ElementClass::Text->new(name => 'issue_id',
                                       max  => 1),
                    Krang::ElementClass::CheckBox->new(name => 'enhanced_content',
                                           @fixed),
                    PBMM::promo->new(),
                    Default::lead_in->new(),
                    PBMM::image->new(),
                    Krang::ElementClass::Text->new(name         => "small_header" ),
                    Krang::ElementClass::Text->new(name         => "large_header" ),   
                    Krang::ElementClass::Textarea->new(name => "paragraph",
                                                    bulk_edit => 1,
                                                   ),
                    PBMM::double_cover_column->new(   name => "double_column" ), 

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
