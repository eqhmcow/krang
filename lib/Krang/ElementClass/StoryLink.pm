package Krang::ElementClass::StoryLink;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass';
use Krang::ClassLoader Log => qw(debug info critical);

#use Krang::MethodMaker
#  get_set => [ qw( ) ];

sub new {
    my $pkg = shift;
    my %args = ( 
                lazy_loaded => 1,
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
        my ($story) = pkg('Story')->find(story_id => $story_id);
        $html .= qq{<div style="padding-bottom: 2px; margin-bottom: 2px; border-bottom: solid #333333 1px">} .
          qq{Title: "} . $story->title . qq{"<br>} . 
          qq{URL: <a href="javascript:preview_story($story_id)">} . pkg('Widget')->can('format_url')->(url => $story->url, length => 30) . qq{</a></div>};
    }


    $html .= scalar $query->button(-name    => "find_story_$param",
                                   -value   => "Find Story",
                                   -onClick => "find_story('$param')",
				   -class   => "button",
                                  );
    return $html;
}

# due to the unusual way that story links get their data, a story link
# is invalid only if required and it doesn't already have a value.
sub validate {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    if ($self->{required} and not defined $element->data) {
        return (0, "$self->{display_name} requires a value.");
    }
    return 1;
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
        $html .= qq{Title: "} . $story->title . qq{"<br>} . 
          qq{URL: <a href="javascript:preview_story($story_id)">} . $story->url . qq{</a>};
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
    my ($story) = pkg('Story')->find(story_id => $data);
    return $element->data($story);
}

# do the normal XML serialization, but also include the linked story
# object in the dataset
sub freeze_data_xml {
    my ($self, %arg) = @_;
    my ($element, $writer, $set) = @arg{qw(element writer set)};
    $self->SUPER::freeze_data_xml(%arg);

    # add object
    my $story = $element->data;
    $set->add(object => $story, from => $element->object) if $story;
}


# translate the incoming story ID into a real ID
sub thaw_data_xml {
    my ($self, %arg) = @_;
    my ($element, $data, $set) = @arg{qw(element data set)};

    my $import_id = $data->[0];
    return unless $import_id;
    my $story_id = $set->map_id(class => 'Krang::Story',
                                id    => $import_id);
    $self->thaw_data(element => $element,
                     data    => $story_id);
}

# overriding Krang::ElementClass::template_data
# checks the publish status, returns url or preview_url, depending.
#
# If the element is not properly linked to a story, returns nothing.
#
sub template_data {
    my $self = shift;
    my %args = @_;

    my $data = $args{element}->data();
    if( $data ) {
        if ($args{publisher}->is_publish()) {
            return 'http://' . $data->url();
        } elsif ($args{publisher}->is_preview()) {
            return 'http://' . $data->preview_url();
        } else {
            croak (__PACKAGE__ . ': Not in publish or preview mode. Cannot return proper URL.');
        }
    }
}

#
# If fill_template() has been called, a template exists for this element.
# Populate it with available attributes - story title & url.
#
# See Krang::ElementClass->fill_template for more information.
#
sub fill_template {
    my $self = shift;
    my %args = @_;

    my $tmpl      = $args{tmpl};
    my $publisher = $args{publisher};
    my $element   = $args{element};

    my %params = ();

    $params{title} = $element->data()->title()
      if $tmpl->query(name => 'title');

    $params{url} = $element->template_data(publisher => $publisher);

    $tmpl->param(\%params);

}



=head1 NAME

Krang::ElementClass::StoryLink - story link element class

=head1 SYNOPSIS

   $class = pkg('ElementClass::StoryLink')->new(name => "leadin")

=head1 DESCRIPTION

Provides an element to link to a story.  Elements of this class store
a reference to the story in data().

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.

=over

=back

=cut

1;
