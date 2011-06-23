package Krang::ElementClass::StoryLink;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass';
use Krang::ClassLoader Log  => qw(debug info critical);
use Krang::ClassLoader Conf => qw(PreviewSSL);
use Krang::ClassLoader 'URL';
use Krang::ClassLoader Localization => qw(localize);

# For *Link hard find feature
use Storable qw(nfreeze);
use MIME::Base64 qw(encode_base64);

use Krang::ClassLoader MethodMaker => hash => [qw( find )];

sub new {
    my $pkg  = shift;
    my %args = (
        lazy_loaded => 1,
        @_
    );

    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $html = "";

    # show Title and URL for stories
    my $story = $element->data();
    if ($story) {
        my $story_id = $story->story_id;
        my ($story) = pkg('Story')->find(story_id => $story_id);
        $html .=
          qq{<div style="padding-bottom: 2px; margin-bottom: 2px; border-bottom: solid #333333 1px">}
          . localize('Title:') . ' "'
          . $story->title
          . qq{"<br>}
          . localize('URL:')
          . qq{ <a href="" class="story-preview-link" name="story_$story_id">}
          . pkg('Widget')->can('format_url')->(url => $story->url, length => 30)
          . qq{</a></div>};
    }

    $html .= scalar $query->button(
        -name    => "find_story_$param",
        -value   => localize("Find Story"),
        -onClick => "find_story_link('$param')",
        -class   => "button",
    );

    # Add hard find parameters
    my $find = encode_base64(nfreeze(scalar($self->find())));
    my $hard_find_param = $query->hidden("hard_find_$param", $find);
    $html .= $hard_find_param;

    return $html;
}

# due to the unusual way that story links get their data, a story link
# is invalid only if required and it doesn't already have a value.
sub validate {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    if ($self->{required} and not defined $element->data) {
        return (0, localize($self->display_name) . ' ' . localize('requires a value.'));
    }
    return 1;
}

sub view_data {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $html = "";

    # show Title and URL for stories
    my $story = $element->data();
    if ($story) {
        my $story_id = $story->story_id;
        $html =
            localize('Title:') . ' "'
          . $story->title
          . qq{"<br>}
          . localize('URL:')
          . qq{ <a href="" class="story-preview-link" name="story_$story_id">}
          . $story->url
          . qq{</a>};
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
    my ($self,    %arg)  = @_;
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
    my $story_id = $set->map_id(
        class => pkg('Story'),
        id    => $import_id
    );
    $self->thaw_data(
        element => $element,
        data    => $story_id
    );
}

# overriding Krang::ElementClass::template_data
# checks the publish status, returns url or preview_url, depending.
#
# If the element is not properly linked to a story, returns nothing.
#
sub template_data {
    my $self = shift;
    my %args = @_;

    return $args{publisher}->url_for(
        object => $args{element}->data,
    );
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

In addition to the normal interfaces, Krang::ElementClass::StoryLink also 
supports a "find" parameter.  This parameter allows you to specify a
"hard filter" which is used to limit the scope of the universe of 
stories from which the user may select.  For example:

  # Only articles
  my $c = Krang::ElementClass::StoryLink->new(
                name => 'related_articles',
                find => { class => 'article' }
  );


  # Only articles about cats
  my $c = Krang::ElementClass::StoryLink->new(
                name => 'related_articles',
                find => { class => 'article',
                          title_like => '%cats%' }
  );

Any find parameters which are permitted by Krang::Story may be used
by Krang::ElementClass::StoryLink's "find" parameter.


=over

=back

=cut

1;
