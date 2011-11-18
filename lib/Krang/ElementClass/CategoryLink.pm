package Krang::ElementClass::CategoryLink;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base         => 'ElementClass';
use Krang::ClassLoader Log          => qw(debug info critical);
use Krang::ClassLoader Conf         => qw(PreviewSSL);
use Krang::ClassLoader Localization => qw(localize);
use Krang::ClassLoader 'URL';

use Krang::MethodMaker
  get_set => [ qw(publish_if_modified_story_in_cat
                  publish_if_modified_story_below_cat
                  publish_if_modified_media_in_cat
                  publish_if_modified_media_below_cat) ];

sub new {
    my $pkg  = shift;
    my %args = (@_);

    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    # show category chooser
    eval "require " . pkg('Widget') or die $@;
    my $category = $element->data();
    (my $name = $param) =~ s/\W//g;
    $query->param($param => $category->category_id) if $category;
    my ($html, $chooser) = pkg('Widget')->can('category_chooser')->(
        name  => $name,
        field => $param,
        query => $query
    );
    $html .= qq{<input type="hidden" name="$param" }
      . ($category ? q{value="} . $category->category_id . q{"} : '') . q{>};
    return ($html, $chooser);
}

sub validate {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $value = $query->param($param);

    # don't allow self references
    my $object = $element->object;
    if (    $object->isa('Krang::Category')
        and $value
        and $value == $object->category_id)
    {
        return (0, localize($self->display_name) . ' ' . localize('cannot link to this category!'));
    }

    return $self->SUPER::validate(%arg);
}

sub load_query_data {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $value = $query->param($param);
    if ($value) {
        $element->data(pkg('Category')->find(category_id => $value));
    } else {
        $element->data(undef);
    }
}

sub view_data {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $html = "";

    # show Title and URL for stories
    my $category = $element->data();
    if ($category) {
        $html .= $category->url;
    }

    return $html;
}

# store ID of object in the database
sub freeze_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    my $category = $element->data;
    return undef unless $category;
    return $category->category_id;
}

# load object by ID, ignoring failure since the object might have been
# deleted
sub thaw_data {
    my ($self,    %arg)  = @_;
    my ($element, $data) = @arg{qw(element data)};
    return $element->data(undef) unless $data;
    my ($category) = pkg('Category')->find(category_id => $data);
    return $element->data($category);
}

# do the normal XML serialization, but also include the linked category
# object in the dataset
sub freeze_data_xml {
    my ($self, %arg) = @_;
    my ($element, $writer, $set) = @arg{qw(element writer set)};
    $self->SUPER::freeze_data_xml(%arg);

    # add object
    my $category = $element->data;
    $set->add(object => $category, from => $element->object) if $category;
}

# translate the incoming category ID into a real ID
sub thaw_data_xml {
    my ($self, %arg) = @_;
    my ($element, $data, $set) = @arg{qw(element data set)};

    my $import_id = $data->[0];
    return unless $import_id;
    my $category_id = $set->map_id(
        class => pkg('Category'),
        id    => $import_id
    );
    $self->thaw_data(
        element => $element,
        data    => $category_id
    );
}

# overriding Krang::ElementClass::template_data
# checks the publish status, returns url or preview_url, depending.
sub template_data {
    my $self = shift;
    my %args = @_;

    return $args{publisher}->url_for(
        object => $args{element}->data,
    );
}

#
# If fill_template() has been called, a template exists for this element.
# Populate it with the category url.
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

    $params{url} = $element->template_data(publisher => $publisher);

    $tmpl->param(\%params);

}

=head1 NAME

Krang::ElementClass::CategoryLink - category link element class

=head1 SYNOPSIS

   $class = pkg('ElementClass::CategoryLink')->new(name => "leadin")

=head1 DESCRIPTION

Provides an element to link to a category.  Elements of this class store
a reference to the category in data().

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.

=over

=back

=cut

1;
