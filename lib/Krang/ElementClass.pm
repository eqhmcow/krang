package Krang::ElementClass;
use strict;
use warnings;

use Carp qw(croak);
use CGI ();

use HTML::Template::Expr;
use Krang::Log qw(debug info critical);



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
through the standard Krang::MethodMaker accessors.  Sub-classes may
add new attributes as needed to implement their functionality, but
these will always be available.

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
described below.  Furthermore, classes marked for bulk editing must
not have a max value set.

=item required

If set to 1 then the user must fill in a value for this element in the
UI.  Sub-classes should use this flag within their validate() methods.
See C<validate()> for more details.  Defaults to 0.

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
        if (ref $arg and UNIVERSAL::isa($arg, 'Krang::ElementClass')) {
            # it's an object already, push it along
            push(@children, $arg);
            $children_by_name{$arg->{name}} = $arg;
        } else {
            # it's the name of an element, load it
            my $class = Krang::ElementLibrary->find_class(name => $arg);
            croak("Unable to find element class named '$arg' while instantiating '$self->{name}'.")
              unless $class;
            push(@children, $class);
            $children_by_name{$arg} = $class;
        }
    }

    $self->{children_by_name} = \%children_by_name;
    return $self->{children} = \@children;
}

=head2 STATIC OBJECT METHODS

The following methods are available on all Krang::ElementClass
objects, and should not be overriden in sub-classes.

=over

=item C<< $child = $class->child($name) >>

Finds and returns a child by name.  This is faster than calling
C<children()> and looping through the results calling C<name()> if all
you need is a particular child class.

=cut

sub child { 
    my $class = $_[0]->{children_by_name}{$_[1]};
    croak("No class named '$_[1]' found in child class list for '" . 
          $_[0]->name . "'")
      unless defined $class;
    return $class;
}

=item C<< $bool = $class->is_container >>

Returns true if the element class has children.

=cut

sub is_container {
    my $self = shift;
    return @{$self->{children}} ? 1 : 0;
}

=back

=head2 OBJECT METHODS TO OVERRIDE

The following methods are available on all Krang::ElementClass
objects.  All of these methods may be overridden in child classes to
specialize the behavior of an element class.

=over

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

=item C<< @names = $class->param_names(element => $element) >>

Returns the CGI parameter names that will be used for the element.
The default implementation returns a single parameter name of 
C<< $element->xpath() >>.  If you create a sub-class with multiple form
inputs you will need to override this method.

=cut

sub param_names { $_[2]->xpath(); }

=item C<< @data = $class->bulk_edit_data(element => $element) >>

Return an array of text blocks suitable for bulk editing.  This method
must work for all classes that set bulk_edit to 1.  The default
implementation just returns $element->data.

=cut

sub bulk_edit_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    return $element->data;
}

=item C<< @data = $class->bulk_edit_filter(data => \@data) >>

Given an array of text blocks, return an array of scalars suitable for
passing individually to data().  The data passed to this method comes
from the bulk edit text field and has been pre-split on the chosen
separator.  This method must transform this data into a format
suitable for data().  The default implementation returns the data
as-is.

=cut

sub bulk_edit_filter {
    my ($self, %arg) = @_;
    my ($data) = @arg{qw(data)};
    return @$data;
}

=item C<< $html = $class->view_data(element => $element) >>

Called to return the HTML to use in the element view screen.  This is
a static representation of the data in an element.  The default
implementation returns the contents of C<< $element->data >> with all
HTML tags escaped for display.

=cut

sub view_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    return "" . CGI->escapeHTML($element->data || "");
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
After this call, C<< $element->data() >> must return the value
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

=item C<< $url = $class->build_url(story => $story, category => $category) >>

Builds a URL for the given story and category.  The default
implementation takes the category url and appends a URI encoded copy
of the story slug.  This may be overriden by top level elements to
implement alternative URL schemes.  See L<Krang::ElementClass::Cover>
for an example.

=cut

sub build_url {
    my ($self, %arg) = @_;
    my ($story, $category) = @arg{qw(story category)};
    croak("Category not defined!") unless $category;
    return $category->url . CGI::Util::escape($story->slug || '');
}

=item C<< @fields = $class->url_attributes() >>

Returns a list of Story attributes that are being used to compute the
url in build_url().  For example, the default implementation returns
('slug') because slug is the only story attribute used in the URL.
Krang::ElementClass::Cover returns an empty list because it uses no
story attributes in its C<build_url()>.

=cut

sub url_attributes { ('slug') }

=item C<< $class->check_data(element => $element, data => $data) >>

This method is called when C<< $element->data() >> is called to set a
new value for the element.  It may be used to validate the data, in
which case it should croak() if the data is invalid.  Classes which
require a particular data structure in C<< $element->data() >> should
override this method.  The default implementation does nothing.

=cut

sub check_data {}

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

=item C<< @schedules = $class->default_schedules(element => $element, story_id ==> $story_id) >>

Called when a top-level object is created.  May return a list of
Krang::Schedule objects.  The default implementation returns and empty
list.

=cut

sub default_schedules { return (); }

=item C<< $file_name = $class->filename() >>

Returns the filename (independant of the extension) to be used when writing to disk data generated by this element tree.  Will return C<index> unless overridden.

=cut

sub filename {
    return 'index';
}

=item C<< $file_extension = $class->extension() >>

Returns the file extension (see filename()) to be used when writing to disk data generated by this element tree.  Will return C<.html> unless overridden.

=cut

sub extension {
    return 'html';
}



=item C<< $html_tmpl = $class->find_template(element => $element, publisher => $publisher) >>

Part of the publish/output section of Krang::ElementClass.  This call searches the filesystem for the appropriate output template to use with this element.  

If successful, it will return an instantiated HTML::Template::Expr object with the selected template loaded.

The default process by which a template is loaded goes as follows:

=over

=item * 

The name of the template being searched for is $class->name() . ".tmpl"

=item * 

The search starts in the directory $publisher->category->url().

=item * 

If the template is found, it is loaded into an HTML::Template::Expr object.  NOTE - Need rules on checking for deployment/preview settings

=item * 

If the template is not found, move to the parent directory and repeat the search.

=item * 

If the root directory is reached, no template exists.  Croak.

=back

=cut

sub find_template {

    my $self = shift;
    my %args = @_;

    # args for HTML::Template::Expr on instantiation.
    my %tmpl_args = (
                     die_on_bad_params => 0,
                     loop_context_vars => 1,
                     global_vars       => 1
                    );

    # get the category dir from publisher;
    my $publisher = $args{publisher} || croak __PACKAGE__ . ":missing attribute 'publisher'.\n";
    my $element   = $args{element} || croak __PACKAGE__ . ":missing attribute 'element'.\n";

    my $category = $publisher->category();
    my @path = $publisher->template_search_path();

    # Attempt to instantiate an HTML::Template::Expr object with that as the search path.
    my $tmpl = HTML::Template::Expr->new(filename => $element->name() . '.tmpl',
                                         path => \@path,
                                         %tmpl_args
                                        );

    # HTML::Template::Expr will gack if no template has been found.  return template.
    return $tmpl;
}



=item C<< $class->fill_template(element => $element, tmpl => $html_template, publisher => $publisher) >>

Part of the publish/output section of Krang::ElementClass.  This call is responsible for populating the otuput template of the element with the content stored within.  This replaces the "autofill" and .pl files that were found in Bricolage.

The default implementation walks the element tree by calling $child->publish() on all children of the current element.  If you decide to override fill_template, but don't want to deal with the manual work of walking the element tree, make sure to make a call to $self->SUPER::fill_template().

The default implementation populates the template as follows:

=over

=item * 

A single variable is created for $element->name().

=item *

A single variable called $child->name() is created for each B<UNIQUELY NAMED> child element.  For example, if the element contains children named (C<paragraph>, C<paragraph>, C<deck>), two variables would be created, C<paragraph> and C<deck>.  The value of C<paragraph> would correspond to the first paragraph child element.

=item * 

A loop is created for every child element named with the name of the element followed by _loop. The rows of the loop contain the variable described above and a _count variable.

=item * 

A loop called "element_loop" is created with a row for every child element contained. The values are the same as for the loop above with the addition of a boolean is_ variable.

=item * 

A variable for the total number of child elements named with the element name and a trailing _total.

=item * 

A variable called "title" containing $story->title.

=item * 

A variable called "page_break" containing Krang::Publisher->page_break()

=back

=cut

sub fill_template {

    my $self = shift;
    my %args = @_;

    my %element_names = ();

    my $tmpl      = $args{tmpl};
    my $publisher = $args{publisher};
    my $element   = $args{element};

    my $story     = $publisher->story();

    my @element_children = $element->children();

    # build out params going to the template.
    my %params  = (
                   $element->name() => $element->data(),
                   $element->name() . '_total' => scalar(@element_children)
                  );


    # add story title, page break, and content-break tags, if needed.
    $params{title} = $publisher->story()->title()
      if $tmpl->query(name => 'title');

    $params{page_break} = $publisher->page_break()
      if $tmpl->query(name => 'page_break');

    $params{content} = $publisher->content()
      if ($tmpl->query(name => 'content') && $element->name() eq 'category');


    # iterate over the children of the element -
    # This process creates @element_loop, and also creates the various
    # $child->name() _loop loops.
    foreach (@element_children) {
        my $name = $_->name();
        my $html = $_->class->publish(element => $_, publisher => $publisher);
        my $loop_idx = 1;

        unless (exists($element_names{$name})) {
            $element_names{$name} = 1;
            $params{$name} = $html;
        }

        if (exists($params{$name . '_loop'})) { 
            $loop_idx = scalar(@{$params{$name . '_loop'}}) + 1;
        }

        push @{$params{element_loop}}, {
                                        "is_$name" => 1,
                                        $name      => $html
                                       };
        push @{$params{$name . '_loop'}}, {
                                           $name . '_count' => $loop_idx,
                                           $name            => $html,
                                           "is_name"        => 1
                                          };
    }

    $tmpl->param(%params);
}


=item C<< $html = $class->publish(element => $element, publisher => $publisher) >>

The API frontend of the publish/output section of Krang::ElementClass.  This sub builds the HTML represented by this object and the element tree beneath it.  The default implementation ties find_template() and fill_template() together.

If successful, publish() will return a block of HTML.

Generally, you will not want to override publish().  Changes to template-handling behavior should be done by overriding find_template().  Changes to the parameters being passed to the template should be done by overriding fill_template().  Override publish() only in the event that neither of the previous solutions work for you.

=back

=head2 A Note on Elements

=over

Some elements are simply attributes with a value, and no formatting to be associated with them.  This can be because the developer of the element tree wants to handle formatting in the parent element's template, or that there should be no formatting of the data whatsoever (e.g. $element->data() might get embedded in an <input> tag).

In these cases, the element will have no template associated with it - which will cause find_template to fail.  If the element has no children, the value of $element->data() will be returned as the result of the publish() call.  If the element *does* have children, however, publish() will propegate the error thrown by find_template().


=cut


sub publish {

    my $self = shift;
    my %args = @_;

    my $html_template;

    foreach (qw(element publisher)) {
        unless (exists($args{$_})) {
            croak(__PACKAGE__ . ": Missing argument '$_'.  Exiting.\n");
        }
    }

    my $element_id = $args{element}->element_id();

    debug(__PACKAGE__ . ': publish called for element_id=$element_id name=' . $args{element}->name());

    # try and find an appropriate template.
    eval { $html_template = $self->find_template(@_); };

    if ($@) {
        # no template found - if the element has children, this is an error.
        # otherwise, return the raw data stored in the element.
        if (scalar($args{element}->children())) {
            critical(__PACKAGE__ . ": publish() cannot find template for element_id=$element_id");
            croak $@;
        } else {
            return $args{element}->data();
        }
    }

    $self->fill_template(tmpl => $html_template, @_);

    my $html = $html_template->output();

    return $html;
}

=item C<< $class->serialize_xml(element => $element, writer => $writer, set => $set) >>

This call must serialize the element as XML.  The default
implementation uses $element->freeze_data() to get a textual
representation and then produces something like this:

  <element>
    <class>$class->name</class>
    <data>$element->freeze_data</data>   
  </element>

See the Story XML Schema documentation for more details on the
possible forms for element XML.  Also, see the Krang::DataSet
documentation for general information concerning the serialize_xml()
method.

=cut

sub serialize_xml {
    my ($self, %arg) = @_;
    my ($element, $writer, $set) = @arg{qw(element writer set)};

    $writer->startTag('element');    
    $writer->dataElement(class => $self->name());
    my $data = $element->freeze_data();
    $writer->dataElement(data  => $data) if $data;
    foreach my $child ($element->children) {
        $child->serialize_xml(element => $child,
                              writer  => $writer,
                              set     => $set);
    }
    $writer->endTag('element');
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

=head1 TODO

=over

=item *

Modify validate() to throw an exception to indicate failure.

=item *

Implement output (find_template(), fill_template(), publish()).

=back

=cut

1;
