package Krang::ElementClass::StoryLink;
use strict;
use warnings;

use base 'Krang::ElementClass';
use Krang::Log qw(debug info critical);

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
          qq{URL: <a href="javascript:preview_story($story_id)">} . $story->url . qq{</a></div>};
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

    if ($publisher->is_publish()) {
        $params{url} = $element->data()->url();
    } elsif ($publisher->is_preview()) {
        $params{url} = $element->data()->preview_url();
    } else {
        croak (__PACKAGE__ . ': Not in publish or preview mode.  Cannot return proper URL.');
    }

    $tmpl->param(\%params);

}

# Publish - if no template exists, simply return the URL (based on publish/preview status)
#
# See Krang::ElementClass->publish for more information.
sub publish {

    my $self = shift;
    my %args = @_;

    my $html_template;

    foreach (qw(element publisher)) {
        unless (exists($args{$_})) {
            croak(__PACKAGE__ . ": Missing argument '$_'.  Exiting.\n");
        }
    }

    my $publisher = $args{publisher};

    debug(__PACKAGE__ . ': publish called for element name=' . $args{element}->name());

    # try and find an appropriate template.
    eval { $html_template = $self->find_template(@_); };

    if ($@ and $@->isa('Krang::ElementClass::TemplateNotFound')) {
        # no template found.
        # Return the story URL, depending on preview/publish.
        if ($publisher->is_publish()) {
            return $args{element}->data()->url();
        } elsif ($publisher->is_preview()) {
            return $args{element}->data()->preview_url();
        } else {
            croak (__PACKAGE__ . ': Not in publish or preview mode.  Cannot return proper URL.');
        }
    } elsif ($@) {
        # some other error - pass it along.
        die $@;
    }


    $self->fill_template(tmpl => $html_template, @_);

    my $html = $html_template->output();

    return $html;


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
