package PBMM::issue_cover;
use strict;
use warnings;
use PBMM::meta;
use PBMM::promo;
                                                                           
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
   my %args = ( name => 'issue_cover',
                children => [
                    PBMM::story_ocs->new(),
                    PBMM::meta->new(),
                    Krang::ElementClass::Text->new( name => 'issue_id',
                                                    indexed => 1,
                                                    @fixed),
                    Krang::ElementClass::CheckBox->new(name => 'enhanced_content',
                                           @fixed),
                    Krang::ElementClass::CheckBox->new(    name => 'link_to_top_of_page',
                                            default => 1,
                                            min => 1,
                                            max => 1,
                                            allow_delete => 0,
                                            reorderable => 0 ),
                    PBMM::promo->new(),
                    PBMM::custom_search->new(max => 1),
                    PBMM::lead_in->new(),
                    PBMM::external_lead_in->new(),
                    PBMM::image->new(),
                    Krang::ElementClass::Text->new(name         => "small_header" ),
                    Krang::ElementClass::Text->new(name         => "large_header" ),   
                    Krang::ElementClass::Textarea->new(name => "paragraph",
                                                    bulk_edit => 1,
                                                   ),
                    PBMM::table_of_contents->new(),

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
