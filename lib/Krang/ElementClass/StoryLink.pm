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

    # show Title and URL for stories
    my $story = $element->data();
    if ($story) {
        my $story_id = $story->story_id;
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

sub view_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $html = "";

    # show Title and URL for stories
    my $story = $element->data();
    if ($story) {
        my $story_id = $story->story_id;
        my ($story) = Krang::Story->find(story_id => $story_id);
        $html .= qq{Title: "} . $story->title . qq{"<br>} . 
          qq{URL: <a href="#">} . $story->url . qq{</a>};
    }

    return $html;
}

# data isn't loaded from the query.  Instead it arrives indirectly as
# a result of the find_story() routine.
sub load_query_data { } 


# store ID of object in the database
sub freeze_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    my $story = $element->data;
    return undef unless $story;
    return $story->story_id;
}

# load object by ID, ignoring failure since the object might have been
# deleted
sub thaw_data {
    my ($self, %arg) = @_;
    my ($element, $data) = @arg{qw(element data)};
    return $element->data(undef) unless $data;
    my ($story) = Krang::Story->find(story_id => $data);
    return $element->data($story);
}

# do the normal XML serialization, but also include the linked story
# object in the dataset
sub serialize_xml {
    my ($self, %arg) = @_;
    my ($element, $writer, $set) = @arg{qw(element writer set)};
    $self->SUPER::serialize_xml(%arg);

    # add object
    my $story = $element->data;
    $set->add(object => $story) if $story;
}


=head1 NAME

Krang::ElementClass::StoryLink - story link element class

=head1 SYNOPSIS

   $class = Krang::ElementClass::StoryLink->new(name => "leadin")
                                                
=head1 DESCRIPTION

Provides an element to link to a story.  Elements of this class store
a reference to the story in data().

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.

=over

=back

=cut

1;
