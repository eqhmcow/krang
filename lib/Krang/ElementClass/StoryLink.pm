package Krang::ElementClass::StoryLink;
use strict;
use warnings;

use base 'Krang::ElementClass';

#use Krang::MethodMaker
#  get_set => [ qw( ) ];

sub new {
    my $pkg = shift;
    my %args = ( 
                @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $html = "";

    # include thumbnail if media is available
    my $story_id = $element->data();
    if ($story_id) {
        my ($story) = Krang::Story->find(story_id => $story_id);
        $html .= qq{<div style="padding-bottom: 2px; margin-bottom: 2px; border-bottom: solid #333333 1px">} .          
          qq{Title: "} . $story->title . qq{"<br>} . 
          qq{URL: <a href="#">} . $story->url . qq{</a></div>};
    }

    
    $html .= scalar $query->button(-name    => "find_story_$param",
                                   -value   => "Find Story",
                                   -onClick => "find_story('$param')",
                                  );
    return $html;
}

# data isn't loaded from the query.  Instead it arrives indirectly as
# a result of the find_story() routine.
 sub load_query_data { } 


=head1 NAME

Krang::ElementClass::StoryLink - story link element class

=head1 SYNOPSIS

   $class = Krang::ElementClass::StoryLink->new(name => "leadin")
                                                
=head1 DESCRIPTION

Provides an element to link to a story.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.

=over

=back

=cut

1;
