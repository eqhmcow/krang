package Krang::ElementClass;
use strict;
use warnings;

use Carp qw(croak);
use CGI ();

=head1 NAME

Krang::ElementClass - base class for Krang element classes

=head1 SYNOPSIS

  package ElementSet::element_name;
  use base 'Krang::ElementClass';

  # override new() to setup element class parameters
  sub new { 
      my $pkg = shift;
      my %opt = (name => "element_name", @_);
      return $pkg->SUPER::new(%opt); 
  }

  1;

=head1 DESCRIPTION

This class serves as the base class for all Krang Element classes.
Element classes are created by inheriting from this class or one of
its sub-classes (Krang::ElementClass::SelectBox, for example).
Sub-classes must override several methods and setup the required
'name' attribute by overriding C<new()>.

For a higher-level overview of the Krang element system, see
F<docs/element_system.pod>.

=head1 INTERFACE

=head2 OBJECT ATTRIBUTES

Krang::ElementClass objects have the following attributes, available
through the standard Krang::MethodMaker accessors:

=cut

use Krang::MethodMaker
  new_with_init => 'new',
  new_hash_init => 'hash_init',
  get_set       => [ qw( name
                         display_name
                         min
                         max
                         bulk_edit
                         required 
                         reorderable
                         top_level
                         hidden
                         allow_delete
                         default
                       ) ];


=over 4

=item name

The unique name of the element.  Use this instead of C<ref($obj)> to
determine the indentifier for the element class.  Concrete
(non-abstract) descendents of Krang::ElementClass must define a value
for this attribute.

=item display_name

The name that users will see in the story UI when editing this
element.  Defaults to C<ucfirst()>ing each word in C<name> after
splitting on underscores.  Thus, a class with the name
"horizontal_line" has the default C<display_name> "Horizontal Line".

=item min

The minimum number of times the element can appear within another
element.  If this is greater than 0 then instances of this element
will be created when the containing object is created.  Defaults to 0.

=item max

The maximum number of times the element can appear.  Defaults to 0,
meaning any number is allowed.

=item top_level

If the element is a top-level element then this will be set to 1 when
the element class is loaded by Krang::ElementLibrary.  It is not
necessary to set this in sub-classes.  Defaults to 0.

=item hidden

If this attribute is set true then the element will not be available
for use within the UI.  However, it will still function if used by
existing stories or categories.  Defaults to 0.

=item bulk_edit

If set to 1 then this element will be available for bulk_editing.
Sub-classes that set this to 1 must provide the bulk_load() method
described below.

=item required

If set to 1 then the user must fill in a value for this element in the
UI.  Sub-classes should use this flag within their validate() methods.
Defaults to 0.

=item reorderable

If set to 0 then the UI will not allow the user to reorder the
element.  This is generally only useful for elements with min and max
set to 1.  Defaults to 1.

=item allow_delete

If set to 0 then the UI will not allow the element to be deleted.
Defaults to 1.

=item default

A default value for elements of this class.  Will be loaded into their
data slot on creation, so this must be a valid value for the element.

=item children

This attribute is set with an array of the available sub-elements for
the container element.  These elements may be one of two types:

=over

=item * 

A string indicating the names of potential sub-elements.  For example,
C<paragraph> would cause a search through defined element sets for a
class ending in ::paragraph.

=item *

An object belonging to classes descending from Krang::ElementClass.
This allows you to instantiate element classes dynamically.

=back

For example:

  $class->children([ 
                    "paragraph",
                    "image",
                    Krang::ElementClass::Text->new(name => "header"),
                    LA::image_group->new(location => "bottom"),
                   ]);

Although both scalars and objects are valid inputs to children(), only
fully constructed objects will be returned from the accessor.

=back

=cut

# the children attribute decodes its input, instantiating element
# classes where needed
sub children {
    my $self = shift;
    return @{$self->{children}} unless @_;

    my @children;
    my %children_by_name;
    foreach my $arg (@{$_[0]}) {
        if (ref $arg) {
            # it's an object already, push it along
            push(@children, $arg);
            $children_by_name{$arg->{name}} = $arg;
        } else {
            # it's the name of an element, load it
            push(@children, Krang::ElementLibrary->find_class(name => $arg));
            $children_by_name{$arg} = $children[-1];
        }
    }

    $self->{children_by_name} = \%children_by_name;
    return $self->{children} = \@children;
}

=head2 OBJECT METHODS

The following methods are available on all Krang::ElementClass
objects.  All of these methods may be overridden in child classes to
specialize the behavior of an element class.

=over

=item C<< @names = $class->param_names(element => $element) >>

Returns the CGI parameter names that will be used for the element.
The default implementation returns a single parameter name of 
C<< $element->xpath() >>.  If you create a sub-class with multiple form
inputs you will need to override this method.

=cut

sub param_names { $_[2]->xpath(); }

=item C<< $html = $class->input_form(element => $element, query => $query) >>

This call is used to display an HTML form element for data entry in
the frontend.  It must return the HTML text to be used.  The default
implementation returns a hidden field.

=cut

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    return scalar $query->hidden(name     => $param,
                                 default  => ($element->data() || ""),
                                 override => 1);
}

=item C<< ($bool, $msg) = $class->validate(element => $element, query => $query) >>

Given the CGI.pm query object from a form submission, this call must
return true of the input is valid for the element and false if not.
If false, an error message should be returned as well, describing the
error.

The default implementation respects the C<required> attribute but
otherwise does no checking of the input data.

=cut

sub validate { 
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $value = $query->param($param);
    if ($self->{required} and (not defined $value or not length $value)) {
        return (0, "$self->{display_name} requires a value.");
    }
    return 1;
}

=item C<< $class->load_query_data(element => $element, query => $query) >>

This call loads the data from the current query into the object.
Which this call returns C<< $element->data() >> must return the value
specified by the user in the form fields provided by
C<display_form()>.

The default implementation loads data from the query using
C<$element->data()> for this element's parameter.

=cut

sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    $element->data(scalar $query->param($param));
}

=item C<< $html = $class->burn($element) >>

This call allows the class to implement custom code for the burn
process.  This replaces the .pl files found in Bricolage.

The default implementation loads a template named C<$class->name
. ".tmpl">.  It then sets up the standard variables and loops provided
to templates.  See the template tutorial for more information.

=cut

=item C<< $url = $class->build_url(story => $story, category => $category) >>

Builds a URL for the given story and category.  The default
implementation takes the category url, appends a URI encoded copy of
the story slug.  This may be overriden by top_level elements to
implement alternative URL schemes.

=cut

sub build_url {
    my ($self, %arg) = @_;
    my ($story, $category) = @arg{qw(story category)};
    return $category->url . CGI->escape($story->slug);
}

=item C<< @fields = $class->url_attributes() >>

Returns a list of Story attributes that are being used to compute the
url in build_url().  For example, the default implementation returns
('slug') because slug is the only story attribute used in the URL.
Krang::ElementClass::Cover returns an empty list because it uses no
story attributes in its C<build_url()>.

=cut

sub url_attributes { ('slug') }

=item C<< $text = $class->freeze_data(element => $element) >>

Custom serialization of data from the element.  This is used to store
data in the database and for story serialization. 

The default implementation returns C<< $element->data() >> as-is.

=cut

sub freeze_data { $_[2]->data() }

=item C<< $class->thaw_data(element => $element, data => $text) >>

Custom deserialization of data, yeilding an element of this class.
This is used to load data from the database and in loading serialized
stories.

The default implementation just calls C<< $element->data($text) >>.

=cut

sub thaw_data { 
    # I am a bad man
    return $_[2]->data($_[4]) if $_[1] eq 'element';
    return $_[4]->data($_[2]);
}

=item C<< $class_copy = $class->clone() >>

Creates a copy of this class instantiation.  The default
implementation just does a hash copy.  Element classes with more
complex internal structures will need to override this method.

=cut

sub clone {
    my $self = shift;
    return bless({%$self}, ref($self));
}

=item C<< $child = $class->child($name) >>

Finds and returns a child by name.  This is faster than calling
C<children()> and looping through the results calling C<name()> if all
you need is a particular child class.

=cut

sub child { 
    my $class = $_[0]->{children_by_name}{$_[1]};
    croak("No class named '$_[1]' found in child class list for '" . 
          $_[0]->display_name . "'")
      unless defined $class;
    return $class;
}

=back

=cut

# setup defaults and check for required paramters
sub init {
    my $self = shift;
    my %args = @_;

    croak(ref($self) . "->new() called without required name parameter.")
      unless $args{name};

    # display_name defaults to ucfirst on each word in name, split on _
    $args{display_name} = join " ", 
      map { ucfirst($_) } 
        split /_/, $args{name}
          unless exists $args{display_name};

    # setup defaults for unset parameters
    $args{min}       = 0  unless exists $args{min};
    $args{max}       = 0  unless exists $args{max};
    $args{bulk_edit} = 0  unless exists $args{bulk_edit};
    $args{required}  = 0  unless exists $args{required};
    $args{children}  = [] unless exists $args{children};
    $args{top_level} = '' unless exists $args{top_level};
    $args{hidden}    = 0  unless exists $args{hidden};
    $args{reorderable} = 1  unless exists $args{reorderable};
    $args{allow_delete} = 1  unless exists $args{allow_delete};
    $args{default} = undef  unless exists $args{default};

    # call generated inititalizer
    $self->hash_init(%args);

    return $self;
}

sub is_container {
    my $self = shift;
    return @{$self->{children}} ? 1 : 0;
}

=head1 TODO

=over

=item Add tests for build_url() once Krang::Category is in.

=back

=cut

1;
