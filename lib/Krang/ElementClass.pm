package Krang::ElementClass;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Carp qw(croak);
use CGI ();

use HTML::Template::Expr;
use Encode qw(decode_utf8 encode_utf8);

use Krang::ClassLoader Log          => qw(debug info critical);
use Krang::ClassLoader Conf         => qw(PreviewSSL EnablePreviewEditor);
use Krang::ClassLoader Localization => qw(localize);
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader 'MyPref';

use Exception::Class
  'Krang::ElementClass::TemplateNotFound' =>
  {fields => ['element_name', 'template_name', 'included_file', 'category_url', 'error_msg']},

  'Krang::ElementClass::TemplateParseError' =>
  {fields => ['element_name', 'template_name', 'category_url', 'error_msg']},

  'Krang::ElementClass::PublishProblem' => {fields => ['element_name', 'error_msg']};

=head1 NAME

Krang::ElementClass - base class for Krang element classes

=head1 SYNOPSIS

  package ElementSet::element_name;
  use Krang::ClassLoader base => 'ElementClass';

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

use Krang::ClassLoader MethodMaker => new_with_init => 'new',
  new_hash_init                    => 'hash_init',
  get_set                          => [
    qw( name
      min
      display_name
      max
      bulk_edit
      bulk_edit_tag
      before_bulk_edit
      before_bulk_save
      required
      reorderable
      allow_delete
      default
      pageable
      indexed
      lazy_loaded
      _hidden
      )
  ];

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

=item hidden

If this attribute is set true then the element will not be available
for use within the UI.  However, it will still function if used by
existing stories or categories.  Defaults to 0.

If set as a subroutine reference, then it will be called and the value
returned will be used.

=item bulk_edit

If set to 1 or to the string 'textarea' then this element will be
available for bulk_editing in one big textarea.  Classes marked for
bulk editing must not have a max value set. See
L<Krang::BulkEdit::Textarea>.

If set to 'xinha', the textarea will be replaced with a Xinha
editor. See also 'bulk_edit_tag'.

If one or more siblings of the elementclass also have this attribute
set to 'xinha', the bulk edit drop down menu of these elements' parent
will have an additional entry 'All WYSIWYG Elements'.  This will put
the data of all corresponding elements into the Xinha edit area, using
the 'bulk_edit_tag' to identify the data's elementclass.

=item bulk_edit_tag

If 'bulk_edit' is set to 'xinha', this attribute might be set to any
B<allowed> block-level HTMLElement, including

  p, ul, ol, h1, h2, h3, h4, h5, h6, hr, table, address, blockquote pre

For a discussion of what is B<allowed> see the documentation for the
class method C<html_scrubber> in L<Krang::BulkEdit::Xinha::Config>.

Besides of formatting the element's data when displayed in Xinha, this
tag marks the data as belonging to its elementclass. Block elements
that do not have their own elementclass will be put in an elementclass
having the bulk_edit_tag 'p'. If no such class exists, a class having
its 'name' attribute set to 'paragraph' will be used. If none is
found, Krang croaks.

See L<Krang::BulkEdit::Xinha>.

=item before_bulk_edit

This attribute may be used in conjunction with Xinha-based bulk
editing (see bulk_edit above). It takes a coderef allowing to
modify the element's data just before passing it to Xinha. The coderef
receives the element object as its sole argument (see the example
below).

 B<Example:>

 (Prepending 'Correction: ' before to element's data when bulk editing it)

    pkg('ElementClass::Textarea')->new(
        name          => 'correction',
        cols          => 30,
        rows          => 4,
        bulk_edit     => 'xinha',
        bulk_edit_tag => 'pre',
        before_bulk_edit => sub {
            my (%arg) = @_;
            my $element = $arg{element};
            return "Correction: " . $element->data;
        },

This kind of "before edit modification" may be used together with the
attribute C<before_bulk_save>.

=item before_bulk_save

This attribute takes a coderef as its value which is passed the data
about to be saved in the element's data slot.  It may be used to
modify the data coming from Xinha's bulk edit area just before saving
it.

 B<Example:>

 (Stripping 'Correction: ' before saving the element's data

            pkg('ElementClass::Textarea')->new(
                name          => 'correction',
                cols          => 30,
                rows          => 4,
                bulk_edit     => 'xinha',
                bulk_edit_tag => 'pre',
                before_bulk_save => sub {
                    my (%arg) = @_;
                    my $data = $arg{data};
                    $data =~ s/^Correction: //;
                    return $data;
                },

This kind of "before save modification" may be used together with the
attribute C<before_bulk_edit>.

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

=item indexed

If set to 1 then the contents of this element will be indexed.
Defaults to 0.  See L<index_data()> for more details.

=item lazy_loaded

If set to 1 then the contents of this element will be thawed only when
needed.  This means that L<thaw_data()> is called when C<data()> is
first called on the object, not when the object is loaded.  Defaults
to 0.

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
                    pkg('ElementClass::Text')->new(name => "header"),
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
            croak(
                "Unable to add child named '$arg->{name}' to $self->{name}: there is already a child with that name."
            ) if exists $children_by_name{$arg->{name}};
            $children_by_name{$arg->{name}} = $arg;
        } else {

            # it's the name of an element, load it
            my $class = pkg('ElementLibrary')->find_class(name => $arg);
            croak("Unable to find element class named '$arg' while instantiating '$self->{name}'.")
              unless $class;
            croak(
                "Unable to add child named '$arg' to $self->{name}: there is already a child with that name."
            ) if exists $children_by_name{$arg};
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
    croak("No class named '$_[1]' found in child class list for '" . $_[0]->name . "'")
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
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    return scalar $query->hidden(
        -name     => $param,
        -default  => ($element->data() || ""),
        -override => 1
    );
}

=item C<< @names = $class->param_names(element => $element) >>

Returns the CGI parameter names that will be used for the element.
The default implementation returns a single parameter name of 
C<< $element->xpath() >>.  If you create a sub-class with multiple form
inputs you will need to override this method.

=cut

sub param_names { $_[2]->xpath(); }

=item C<< $data = $class->bulk_edit_data(element => $element) >>

This method may be used to filter a bulk-edited element's data just
before concatenating it with its siblings' data. It must work for all
classes that set bulk_edit to 1, 'textarea' or 'xinha'.  The default
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

=item C<< $parent->bulk_save_change(class => $child_class, data => $data) >>

This method is called in L<Krang::BulkEdit::Xinha> when bulk saving an
element just before adding a new child. It is passed the elementclass
(not its name) the new child would normally belong to, the data it
would receive and the parent element. Based on these parameters the
name of a sibling class may be calculated, and the data modified. If
this method is overridden, it must return a list containing the
new class and the new data, whether or not they match the old values.
The default implementation returns them unchanged.

=cut

sub bulk_save_change {
    my ($self, %arg) = @_;
    return ($arg{class}, $arg{data});
}

sub view_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    return "" . CGI->escapeHTML($element->data || "");
}

=item C<< ($bool, $msg) = $class->validate(element => $element, query => $query) >>

Given the CGI.pm query object from a form submission, this call must
return true if the input is valid for the element and false if not.
If false, an error message should be returned as well, describing the
error.

The default implementation respects the C<required> attribute but
otherwise does no checking of the input data.

=cut

sub validate {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $value = $query->param($param);
    if ($self->{required} and (not defined $value or not length $value)) {
        return (0, localize($self->display_name) . ' ' . localize('requires a value.'));
    }
    return 1;
}

=item C<< ($bool, $msg) = $class->validate_children(element => $element, query => $query) >>

Given the CGI.pm query object from a form submission, this call must
return true if the input is valid for the elements children, taken
collectively and false if not.  If false, an error message should be
returned as well, describing the error.  This method is only called if
all the children return (1) from their validate methods.

The default implementation does nothing.

=cut

sub validate_children {
    return 1;
}

=item C<< $invalid_html = $class->mark_form_invalid(html => $html) >>

This method is used to mark the form fields created by input_form()
invalid when the element fails validate().  The default implementation
wraps the form in C<< <span class="invalid"></span> >>.  This method
may be overridden if the class uses HTML which would be broken by
being wrapped in a span.

=cut

sub mark_form_invalid {
    my ($self, %arg) = @_;
    my ($html) = @arg{qw(html)};
    return qq{<span class="invalid">$html</span>};
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
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    $element->data(scalar $query->param($param));
}

=item C<< $class->check_data(element => $element, data => $data) >>

This method is called when C<< $element->data() >> is called to set a
new value for the element.  It may be used to validate the data, in
which case it should croak() if the data is invalid.  Classes which
require a particular data structure in C<< $element->data() >> should
override this method.  The default implementation does nothing.

=cut

sub check_data { }

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

=item C<< $index_data = $class->index_data(element => $element) >>

=item C<< @index_data = $class->index_data(element => $element) >>

This method is used when the C<indexed> attribute is true.  Elements
which are indexed may be used in calls to Krang::Story->find().  The
return value is limited to 256 characters in length.  A list of
strings may be returned which will index against multiple values.  The
default implementation returns C<< $element->freeze_data() >>.

=cut

sub index_data { $_[2]->freeze_data() }

=item C<< $template_data = $class->template_data() >>

This method returns the data associated with the element, formatted
for use in an output template.  In most cases, what
$element->template_data() returns is identical to $element->data(),
but some element classes may override this method to return something
different.

=cut

sub template_data {
    my $self = shift;
    my %args = @_;

    croak("Element parameter not defined!") unless $args{element};
    return $args{element}->data();
}

=item C<< $class->linked_stories(element => $element, publisher => $publisher, story_link => $story_links) >>

This method allows elementclasses such as text fields or WYSIWYG
editors to hook into the publishers linked-stories-mechanism.  The
$story_link hashref passed in is supposed to be filled with key/value
pairs mapping story IDs to story objects. The default implementation
does nothing. For an example implementation see
L<Krang::ElementClass::PoorText> and the latter's template_data()
method.

=cut

sub linked_stories { }

=item C<< $filtered = $class->filter_element_data(element => $element, query => $query) >>

This method is called by L<Krang::CGI::ElementEditor>'s dispatcher
method filter_element_data(). It should return the filtered
(scrubbed/sanitized/cleaned) data for the element it recieves. The
default implementation returns the element's data as-is.

=cut

sub filter_element_data {
    my ($self, %args) = @_;

    # get HTML to be cleaned
    my $element = $args{element};
    my ($param) = $self->param_names(element => $element);
    my $html = $args{query}->param($param) || '';

    return $html;
}

=item C<< $html_tmpl = $class->find_template(element => $element, publisher => $publisher) >>

Part of the publish/output section of Krang::ElementClass.  This call searches the filesystem for the appropriate output template to use with this element.  

If successful, it will return an instantiated HTML::Template::Expr object with the selected template loaded.

Parameters are as follows:

=over

=item *

C<publisher> - The L<Krang::Publisher> object handling the current publish run.

=item *

C<element> - The element currently being published - a L<Krang::Element> object.

=item *

C<filename> - The name of the template that should be found.  If this parameter is not set, C<find_template()> will search for C<< $element->name . '.tmpl' >>.

=back

C<publisher> is a required argument, and either C<element> or
C<filename> must be passed in as well.

The default process by which a template is loaded goes as follows:

=over

=item *

The name of the template being searched for is $class->name() . ".tmpl"
Instead of element, filename arg can be passed in, which should correspond 
to the template name you are looking for.

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
    my ($self, %args) = @_;
    my $publisher = $args{publisher}
      || croak __PACKAGE__ . ":missing attribute 'publisher'.\n";
    my $element  = $args{element};
    my $filename = $args{filename};

    croak __PACKAGE__ . ":missing attribute 'element' or 'filename'.\n"
      if (not $element and not $filename);

    my @search_path = $publisher->template_search_path();
    $filename = $element->name() . '.tmpl' if not $filename;

    # this is needed so that element templates don't get Krang's templates
    local $ENV{HTML_TEMPLATE_ROOT} = "";

    # maybe add a utf-8 decoding filter
    if (pkg('Charset')->is_utf8) {
        my @filters = ();
        my $filter  = $args{filter};
        if ($filter) {
            if (ref($filter) eq 'CODE') {
                push @filters, $filter;
            } elsif (ref($filter) eq 'ARRAY') {
                @filters = @$filter;
            } else {
                croak
                  "Filter argument to HTML::Template::Expr must be a code or an array reference, "
                  . "but ref($filter) returned '"
                  . ref($filter) . "'";
            }
        }
        push @filters, sub { ${$_[0]} = decode_utf8(${$_[0]}) };

        # get Preview Editor info from publish context
        my %publish_context = $publisher->publish_context();

        # use template finder if enabled
        if (EnablePreviewEditor && $publisher->is_preview) {
            $args{cms_root} = pkg('Conf')->cms_root;
            $self->_insert_comments_for_template_finder(
                %args,
                filters   => \@filters,
                publisher => $publisher,
                filename  => $filename,
            );
            $self->_insert_preview_editor_top_overlay(
                %args,
                filters => \@filters,
                %publish_context,
            );
        }

        $args{filter} = \@filters;
    }

    # Attempt to instantiate an HTML::Template::Expr object
    my $template;
    eval {
        $template = HTML::Template::Expr->new(
            filename               => $filename,
            path                   => \@search_path,
            die_on_bad_params      => 0,
            loop_context_vars      => 1,
            global_vars            => 1,
            cache                  => 1,
            search_path_on_include => 1,
            %args,
        );
    };
    if ($@) {
        my $err = $@;

        # HTML::Template::Expr is having problems - throw an error
        # based on the problem reported.
        if ($err =~ /file not found/) {
            my ($included_file) = $err =~ /Cannot open included file (\S+)/;
            Krang::ElementClass::TemplateNotFound->throw(
                message       => "Missing required output template: '$err'",
                element_name  => ($element ? localize($element->display_name) : $filename),
                template_name => $filename,
                included_file => (($included_file || '') ne $filename) && $included_file,
                category_url  => $publisher->category->url(),
                error_msg     => $err
            );
        }

        # assuming remaining errors are parse errors at this time.
        else {

            # parse the message - stack traces aren't user-friendly.
            $err =~ /^(.+?)\n[^\n]+Template\:\:Expr/so;
            my $msg = $1;

            Krang::ElementClass::TemplateParseError->throw(
                message       => "Coding error found in template: '$msg'",
                element_name  => ($element ? localize($element->display_name) : $filename),
                template_name => $filename,
                category_url  => $publisher->category->url(),
                error_msg     => $err
            );
        }
    }

    # if we've gotten this far, we have a valid template.
    return $template;
}

=item C<< $class->fill_template(element => $element, tmpl => $html_template, publisher => $publisher) >>

Part of the publish/output section of Krang::ElementClass.  This call
is responsible for populating the output template of the element with
the content stored within.  This replaces the "autofill" and .pl files
that were found in Bricolage.

The default implementation walks the element tree by calling
$child->publish() on all children of the current element.  If you
decide to override fill_template, but don't want to deal with the
manual work of walking the element tree, make sure to make a call to
$self->SUPER::fill_template().

The default implementation populates the template as follows:

=over

=item * 

A single variable is created for C<< $element->name() >>.

=item *

For each B<UNIQUELY NAMED> child element used in the template,
a single variable called C<$childname> is created. For 
example, if the element contains children named (C<paragraph>, 
C<paragraph>, C<deck>), and both <tmpl_var paragraph> and
<tmpl_var deck> are included in the template, two variables 
would be created, C<paragraph> and C<deck>.  The value of C<paragraph> 
would correspond to the first paragraph child element.

=item * 

If the template has a loop named after a specific child 
(e.g. C<page_loop>) it is created as follows: 

If the inside of the loop contains a direct reference to the child
- e.g. <tmpl_var page> - and the child is either a primitive element
or a container for which a separate template exists (e.g. C<page.tmpl>), 
then each row of the loop will contain C<$childname> = HTML, where HTML 
is the result of publishing $child. If not, each row will contain the 
vars returned by $child->fill_template() (i.e. any of its OWN children 
used in the template - <tmpl_var paragraph> etc. - will be populated). 

Either way, each row will also contain the variable $childname_count
(e.g. C<page_count>)

=item * 

If the template contains an C<element_loop> (i.e. <tmpl_loop element_loop>), it 
is created with a row for every child element. The variables are 
the same as for the child-specific loop above with the addition of a boolean 
C<is_$childname>.

(Note: If the template contains multiple instances of the same loop, each will
be populated with identical variables. This means that if ANY of them contains a 
direct reference to the child, they will all have access to C<$childname> = HTML, 
and none will have access to the child's own children.)

=item *

A loop C<contrib_loop> that contains all contributor information.  See
the section on L<Contributors>

=item *

If the element is pageable (see L<Krang::Element>), a series of
variables relating to Pagination.  See the section on L<Pagination>.

=item * 

A variable for the total number of child elements named with the
element name and a trailing _total.

=item * 

A variable called C<title> containing C<< $story->title() >>.

=item *

A variable called C<slug> containing C<< $story->slug() >>.

=item * 

A variable called C<page_break> containing C<< Krang::Publisher->page_break() >>

=item *

A loop C<tag_loop> that contain all of the tags for this story. Each
iteration of the loop contains 1 variable named C<tag>.

=back

B<NOTE:> If you're developing your own elements, be aware that there exists the potential for naming collisions.  For example, if you create a child element named C<title>, you create a collsion with C<< $story->title >>.  Default behavior is that element children take precedence over everything else in a naming collision.  Avoid this by choosing better names for your elements.

=cut

sub fill_template {

    my $self = shift;
    my %args = @_;

    my $tmpl      = $args{tmpl};
    my $publisher = $args{publisher};
    my $element   = $args{element};

    my $story = $publisher->story();

    my @element_children = $element->children();

    # list of variable names in the template -- add element_loop vars if needed
    my %template_vars = map { $_ => 1 } $tmpl->query();
    if (exists($template_vars{element_loop})) {
        delete $template_vars{element_loop};
        my @loop_vars = eval { $tmpl->query(loop => 'element_loop') };
        if( my $e = $@ ) {
            if( $e =~ /non-loop parameter/ ) {
                my $filename = $tmpl->{options}->{filename};
                Krang::ElementClass::TemplateParseError->throw(
                    message       => 'Coding error found in template: element_loop needs to be a TMPL_LOOP',
                    element_name  => ($element ? localize($element->display_name) : $filename),
                    template_name => $filename,
                    category_url  => $publisher->category->url(),
                    error_msg     => $e,
                );
            } else {
                die $e;
            }
        }
        $template_vars{element_loop}{$_} = 1 foreach (@loop_vars);
    }

    # list of child element names that have been seen
    my %element_names = ();

    # build out params going to the template.
    my %params = ($element->name() . '_total' => scalar(@element_children));
    if (my $element_template_data = $element->template_data(publisher => $publisher)) {
        $params{$element->name} = $element_template_data;
    }

    # add story title, slug, cover date, page break, and content-break tags, if needed.
    $params{title} = $publisher->story()->title()
      if exists($template_vars{title});

    $params{slug} = $publisher->story()->slug()
      if exists($template_vars{slug});

    $params{cover_date} =
      $publisher->story()->cover_date()->strftime(localize('%b %e, %Y %l:%M %p'))
      if exists($template_vars{cover_date});

    $params{page_break} = $publisher->page_break()
      if exists($template_vars{page_break});

    $params{content} = $publisher->content()
      if (exists($template_vars{content}) && $element->name() eq 'category');

    # add the contributors loop if desired
    $params{contrib_loop} = $self->_build_contrib_loop(@_)
      if exists($template_vars{contrib_loop});

    # add the tags loop if desired
    $params{tag_loop} = map { { tag => $_ } } $publisher->story->tags()
      if exists($template_vars{tag_loop});

    # add the category trail loop
    $params{category_trail_loop} = $self->_build_cat_trail_loop(@_)
      if exists($template_vars{category_trail_loop});

    # add variables passed in by whatever called $self->publish().
    if (defined($args{fill_template_args})) {
        foreach my $key (keys %{$args{fill_template_args}}) {
            $params{$key} = $args{fill_template_args}{$key}
              if exists($template_vars{$key});
        }
    }

    #
    # Walking the children
    #
    # Walking the children requires two passes - the first to determine if there
    # are any pageable elements, the second to publish.
    #

    my @page_urls   = ();
    my $page_number = 1;

    # scan the children for pageable elements.
    foreach my $child (@element_children) {
        if ($child->pageable) {

            # build the URL for this 'page' - will be used in the publish pass.
            my $count = @page_urls;

            # set protocol to 'https' in preview if running with SSL enabled
            my $scheme = ($publisher->is_preview and PreviewSSL) ? 'https' : 'http';
            push @page_urls,
              $self->_build_page_url(
                page      => $count,
                publisher => $publisher,
                protocol  => $scheme . '://'
              );
        }
    }

    my %element_count;
    my %child_params;

    foreach my $child (@element_children) {
        my $name       = $child->name;
        my $child_loop = $name . '_loop';
        my $html;
        my %fill_template_args;

        # skip this child unless something in the template references
        # it!  e.g. it exists in element loop, a name_loop, or
        # directly in the template, not seen before.
        next
          unless (exists($template_vars{element_loop}{$name})
            || exists($template_vars{element_loop}{"is_$name"})
            || exists($template_vars{$child_loop})
            || (exists($template_vars{$name}) && !exists($child_params{$name})));

        # Pass pagination variables along to child->publish if the
        # child element is pageable (e.g. is used for determining what
        # constitutes a page).
        if ($child->pageable) {
            my $pagination_info = $self->_build_pagination_vars(
                page_list => \@page_urls,
                page_num  => $page_number++
            );

            map { $fill_template_args{$_} = $pagination_info->{$_} } keys %{$pagination_info};

        }

        # if 'element_loop' exists in template, create or append to it
        if (   exists($template_vars{element_loop}{$name})
            || exists($template_vars{element_loop}{"is_$name"}))
        {

            my $loop_idx =
              $element_count{$name} ? ++$element_count{$name} : ($element_count{$name} = 1);
            my $loop_entry = $self->_fill_loop_iteration(
                %args,
                child              => $child,
                html               => \$html,
                loopname           => 'element_loop',
                count              => $loop_idx,
                fill_template_args => \%fill_template_args
            );
            push @{$child_params{element_loop}}, $loop_entry;
        }

        # if "$name_loop" exists in template, create or append to it
        if (exists($template_vars{$child_loop})) {

            my $loop_idx =
              exists($child_params{$child_loop}) ? (@{$child_params{$child_loop}} + 1) : 1;
            my $loop_entry = $self->_fill_loop_iteration(
                %args,
                child              => $child,
                html               => \$html,
                loopname           => $child_loop,
                count              => $loop_idx,
                fill_template_args => \%fill_template_args
            );

            # fix to make contrib_loop available - this is because
            # HTML::Template does not support global loops - only global_vars
            if ($tmpl->query(name => [$child_loop, 'contrib_loop'])) {
                $child_params{contrib_loop} = $self->_build_contrib_loop(@_)
                  unless exists($child_params{contrib_loop});
                $loop_entry->{contrib_loop} = $child_params{contrib_loop};
            }

            push @{$child_params{$child_loop}}, $loop_entry;
        }

        # if the element is used in the template outside of a loop, and
        # hasn't been set (first child element takes precedence), set it.
        if (exists($template_vars{$name}) && !exists($child_params{$name})) {

            # overlay div showing the child's display name
            my $div = $child->is_container && EnablePreviewEditor && $publisher->is_preview
              ? $self->_get_preview_editor_element_overlays(child => $child, publisher => $publisher)
                : '';

            # get html for element, unless it's already built
            $html ||= $child->publish(
                publisher          => $publisher,
                fill_template_args => \%fill_template_args
            );
            $child_params{$name} = $div . ($html || '');
        }
    }

    $tmpl->param(%params, %child_params);
}

# _fill_loop_iteration: helper function called by fill_template which returns a hashref
# of the keys & vals necessary inside an iteration of 'element_loop' or "$child_loop"
sub _fill_loop_iteration {

    my ($self, %args) = @_;

    my $tmpl               = $args{tmpl};
    my $child              = $args{child};
    my $html               = $args{html};
    my $count              = $args{count};
    my $loopname           = $args{loopname};
    my $publisher          = $args{publisher};
    my $fill_template_args = $args{fill_template_args};

    my $name        = $child->name;
    my %loop_filled = (
        $name . '_count' => $count,
        "is_$name"       => 1
    );

    # overlay div showing the child's display name
    my %publish_context = $publisher->publish_context;
    my $div = $child->is_container && EnablePreviewEditor
      ? $self->_get_preview_editor_element_overlays(%args, %publish_context)
      : '';

    # see if inner loop contains a tag for the element itself (ie without '_loop')
    if ($tmpl->query(name => [$loopname, $name])) {

        # it DOES: try publishing the element, and using the resulting html as its value
        eval {
            $$html ||= $child->publish(
                publisher          => $publisher,
                fill_template_args => $fill_template_args
            );
        };
        if (my $err = $@) {
            if ($err->isa('Krang::ElementClass::TemplateNotFound')) {

                # no template could be found; we'll use flattened-template recursion below
            } else {

                # there was an unknown error
                die($err);
            }
        } else {

            # success
            $loop_filled{$name} = $div . ($$html || '');
        }
    }
    unless ($loop_filled{$name}) {

        # it DOESN'T (or the element had no template): recurse to build the inner loop's vars
        foreach my $sub_tmpl (
            values %{$tmpl->{param_map}{$loopname}->[HTML::Template::LOOP::TEMPLATE_HASH]})
        {

          # here we're directly accessing any sub-template(s) HTML::Template built for $loopname....
            $sub_tmpl->clear_params;
            $child->fill_template(
                publisher          => $publisher,
                fill_template_args => $fill_template_args,
                tmpl               => $sub_tmpl,
                element            => $child
            );
            foreach (grep { defined $sub_tmpl->param($_) } $sub_tmpl->param) {
                $loop_filled{$_} =
                  $sub_tmpl->param($_);    # store the values in this iteration of loop
            }
        }
    }
    return \%loop_filled;
}

=item C<< $html = $class->publish(element => $element, publisher => $publisher) >>

The API frontend of the publish/output section of Krang::ElementClass.  This sub builds the HTML represented by this object and the element tree beneath it.  The default implementation ties find_template() and fill_template() together.

If successful, publish() will return a block of HTML.

Generally, you will not want to override publish().  Changes to template-handling behavior should be done by overriding find_template().  Changes to the parameters being passed to the template should be done by overriding fill_template().  Override publish() only in the event that neither of the previous solutions work for you.

B<NOTE>: Some elements are simply attributes with a value, and no
formatting to be associated with them.  This can be because the
developer of the element tree wants to handle formatting in the parent
element's template, or that there should be no formatting of the data
whatsoever (e.g. $element->template_data() might get embedded in an
<input> tag).

In these cases, the element will have no template associated with it -
which will cause find_template to fail.  If the element has no
children, the value of $element->template_data() will be returned as
the result of the publish() call.  If the element *does* have
children, publish() will propagate the error, causing fill_template() 
to make the element's children available directly to its parent's template.


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

    my $publisher = $args{publisher};

    # try and find an appropriate template.
    eval { $html_template = $self->find_template(@_); };

    if (my $err = $@) {
        if ($err->isa('Krang::ElementClass::TemplateNotFound')) {

            # no template found - if the element has children, this is an error.
            # otherwise, return the raw data stored in the element.
            if (scalar($args{element}->children())) {
                $err->rethrow;
            } else {
                return $args{element}->template_data(publisher => $publisher);
            }
        } else {

            # another error occured with the template - re-throw.
            die $err;
        }
    }

    $self->fill_template(tmpl => $html_template, @_);

    # make sure publish returns cleanly
    my $html = eval { $html_template->output() };

    if (my $err = $@) {

        # known output problems involve bad HTML::Template::Expr usage.
        if ($err =~ /HTML::Template::Expr/) {

            # try and parse $err to remove the stack trace.
            $err =~ /^(.*?Expr.*?\n)/so;
            my $msg = $1;

            Krang::ElementClass::TemplateParseError->throw(
                message       => "Error publishing with template: '$msg'",
                element_name  => localize($args{element}->display_name),
                template_name => $args{element}->name . '.tmpl',
                category_url  => $publisher->category->url(),
                error_msg     => $err
            );
        } elsif (ref $err) {

            # something else, but not to be caught here.
            die $err;
        } else {

            # something completely unexpected.
            Krang::ElementClass::PublishProblem->throw(
                element_name => localize($args{element}->display_name),
                error_msg    => $err
            );
        }
    }

    return $html;
}

=item C<< $class->freeze_data_xml(element => $element, writer => $writer, set => $set) >>

This call must serialize the element's data as XML.  The default
implementation uses $element->freeze_data() to get a textual
representation and then produces something like this:

    <data>$element->freeze_data</data>   

The data element is the only valid element that may be written but it
may be repeated multiple times.  For example, a keywords element might
serialize as:

    <data>keyword1</data>
    <data>keyword2</data>
    <data>keyword3</data>

=cut

sub freeze_data_xml {
    my ($self,    %arg)    = @_;
    my ($element, $writer) = @arg{qw(element writer)};

    my $data = $element->freeze_data();
    $writer->dataElement(data => (defined $data and length $data) ? $data : '');
}

=item C<< $class->thaw_data_xml(element => $element, data => $data, set => $set) >>

This call must deserialize the element's data from XML source produced
by freeze_data_xml. The data argument points to an array of strings
produced by parsing the <data> tags with XML::Simple.  For example, if
the source XML is:

    <data>keyword1</data>
    <data>keyword2</data>
    <data>keyword3</data>

Then data witll contain:

  [ "keyword1", "keyword2", "keyword3" ]

The default implementation calls thaw_data() on $data[0].

=cut

sub thaw_data_xml {
    my ($self,    %arg)  = @_;
    my ($element, $data) = @arg{qw(element data)};
    $self->thaw_data(element => $element, data => $data->[0]);
}

=item C<< $class->order_of_available_children() >>

This optional method allows an element class to override Krang's default
behavior of sorting available children (in the 'Add' dropdown) by display name.
If present it can return an array containing the names of optional elements in
the desired order, or an array of hashrefs to include optgroups in the menu.
The hashrefs should have the following structure:

  {
    optgroup => 'My Group',
    elements => [qw(
      element1
      element2
      element3
    )]
  }

=cut

sub order_of_available_children {
    return ();
}

# setup defaults and check for required paramters
sub init {
    my $self = shift;
    my %args = @_;

    croak(ref($self) . "->new() called without required name parameter.")
      unless $args{name};

    # display_name defaults to ucfirst on each word in name, split on _
    $args{display_name} = join " ", map { ucfirst($_) }
      split /_/, $args{name}
      unless exists $args{display_name};

    # setup defaults for unset parameters
    $args{min}              = 0     unless exists $args{min};
    $args{max}              = 0     unless exists $args{max};
    $args{bulk_edit}        = 0     unless exists $args{bulk_edit};
    $args{bulk_edit_tag}    = undef unless exists $args{bulk_edit_tag};
    $args{before_bulk_edit} = undef unless exists $args{before_bulk_edit};
    $args{before_bulk_save} = undef unless exists $args{before_bulk_save};
    $args{required}         = 0     unless exists $args{required};
    $args{children}         = []    unless exists $args{children};
    $args{_hidden}          = 0     unless exists $args{hidden};
    $args{reorderable}      = 1     unless exists $args{reorderable};
    $args{allow_delete}     = 1     unless exists $args{allow_delete};
    $args{default}          = undef unless exists $args{default};
    $args{indexed}          = 0     unless exists $args{indexed};
    $args{lazy_loaded}      = 0     unless exists $args{lazy_loaded};

    # call generated inititalizer
    $self->hash_init(%args);

    return $self;
}

sub hidden {
    my ($self, $val) = @_;

    if( defined $val ) {
        $self->_hidden($val);
    } else {
        $val = $self->_hidden;
    }

    if( ref $val && ref $val eq 'CODE' ) {
        return $val->();
    } else {
        return $val;
    }
}

=item C<< $class->clone_hook(element => $element) >>

Called after the story/category containing the element tree is cloned and just
before it is saved.  The default implementation does nothing.

=cut

sub clone_hook { }

#
# $url = _build_page_url(publisher => $pub, page => $page_num, protocol => 'https://');
#
# Constructs and returns the URL for a specified page in the story.
# All parameters are optional.
# protocol defaults to 'http://' unless otherwise specified.
#

sub _build_page_url {

    my $self = shift;
    my %args = @_;

    my $page_num  = $args{page}      || 0;
    my $publisher = $args{publisher} || $self->{publisher};
    my $protocol  = $args{protocol}  || 'http://';

    my $story = $publisher->story;

    my $base_url;

    if ($publisher->is_publish) {
        $base_url = $story->class->build_url(
            story    => $story,
            category => $publisher->category
        );
    } elsif ($publisher->is_preview) {
        $base_url = $story->class->build_preview_url(
            story    => $story,
            category => $publisher->category
        );
    } else {
        croak __PACKAGE__ . ": Mode unknown - are we in publish or preview mode?";
    }

    return sprintf('%s%s/%s', $protocol, $base_url, $publisher->story_filename(page => $page_num));
}

#
# $pagination_hashref = _build_pagination_vars(page_list => $pages_listref, page_num => $page_num);
#
# Builds the full set of template pagination variables for a given pageable element.
# Takes a list of URLs for all the pages in the story, along with the current page number.
#
# See the Pagination section of docs/writing_htmltemplate.pod for further information on using
# these variables.
#
sub _build_pagination_vars {

    my $self = shift;
    my %args = @_;

    my $page_list = $args{page_list};
    my $page_num  = $args{page_num};

    my $current_idx = $page_num - 1;

    my %page_info;

    $page_info{current_page_number} = $page_num;
    $page_info{total_pages}         = @$page_list;

    $page_info{first_page_url} = $page_list->[0];
    $page_info{last_page_url}  = $page_list->[$#$page_list];

    if ($page_num == 1) {    # on the first page
        $page_info{is_first_page}     = 1;
        $page_info{previous_page_url} = '';
    } else {
        $page_info{is_first_page}     = 0;
        $page_info{previous_page_url} = $page_list->[($current_idx - 1)];
    }

    if ($page_num == @$page_list) {    # on the last page
        $page_info{is_last_page}  = 1;
        $page_info{next_page_url} = '';
    } else {
        $page_info{is_last_page}  = 0;
        $page_info{next_page_url} = $page_list->[($current_idx + 1)];
    }

    for (my $num = 0 ; $num <= $#$page_list ; $num++) {
        my %element = (
            page_number => ($num + 1),
            page_url    => $page_list->[$num]
        );

        ($num == $current_idx)
          ? ($element{is_current_page} = 1)
          : ($element{is_current_page} = 0);

        push @{$page_info{pagination_loop}}, \%element;

    }

    return \%page_info;
}

#
# builds loop of story's category and parent categories

sub _build_cat_trail_loop {
    my $self = shift;
    my %args = @_;

    my @category_loop;

    my $object = $args{element}->object;
    my $base_cat = $object->isa('Krang::Story') ? $object->category : $object;

    push(@category_loop,
        {display_name => $base_cat->element->child('display_name')->data, url => $base_cat->url});

    while ($base_cat->parent) {
        $base_cat = $base_cat->parent;
        unshift(
            @category_loop,
            {
                display_name => $base_cat->element->child('display_name')->data,
                url          => $base_cat->url
            }
        );
    }

    return \@category_loop;
}

#
# builds the loop of contributors for the currently published story.
# See docs/writing_htmltemplate.pod for more information about the final structure
# of the contrib_loop.
#
sub _build_contrib_loop {

    my $self = shift;
    my %args = @_;

    my %contrib_types = pkg('Pref')->get('contrib_type');

    my %contribs      = ();
    my @contributors  = ();
    my @contrib_order = ();

    my $publisher = $args{publisher};

    # get the contributors for the story.
    foreach my $contrib ($publisher->story()->contribs()) {
        my $cid = $contrib->contrib_id();

        # check to see if this contributor exists - if so, save
        # on querying for information you already know.
        unless (exists($contribs{$cid})) {

            # preserve the order in which the contributors arrive.
            push @contrib_order, $cid;
            $contribs{$cid}{contrib_id} = $cid;
            $contribs{$cid}{prefix}     = $contrib->prefix();
            $contribs{$cid}{first}      = $contrib->first();
            $contribs{$cid}{middle}     = $contrib->middle();
            $contribs{$cid}{last}       = $contrib->last();
            $contribs{$cid}{suffix}     = $contrib->suffix();
            $contribs{$cid}{email}      = $contrib->email();
            $contribs{$cid}{phone}      = $contrib->phone();
            $contribs{$cid}{bio}        = $contrib->bio();
            $contribs{$cid}{url}        = $contrib->url();
            $contribs{$cid}{full_name}  = $contrib->full_name();

            my $media = $contrib->image();
            if (defined($media)) {
                if ($publisher->is_preview) {
                    $contribs{$cid}{image_url} = $media->preview_url();
                } elsif ($publisher->is_publish) {
                    $contribs{$cid}{image_url} = $media->url();
                }
            }
        }

        # add the selected contributor type to the contrib_type_loop
        my $contrib_type_id = $contrib->selected_contrib_type();
        push @{$contribs{$cid}{contrib_type_loop}},
          {
            contrib_type_id   => $contrib_type_id,
            contrib_type_name => $contrib_types{$contrib_type_id}
          };

    }

    foreach my $contrib_id (@contrib_order) {
        push @contributors, $contribs{$contrib_id};
    }

    return \@contributors;
}

sub _insert_comments_for_template_finder {
    my ($self, %args) = @_;
    my ($filters, $publisher, $filename) = @args{ qw(filters publisher filename) };
    my $category = $publisher->category;
    my $tmpl;

    # find the template that will actually be used
    for my $cat ($category, $category->ancestors) {
        ($tmpl) = pkg('Template')->find(category_id => $cat->category_id,
                                        filename    => $filename);
        last if $tmpl;
    }

    # no template? maybe we've got a root template
    unless ($tmpl) {
        ($tmpl) = pkg('Template')->find(filename => $filename);
    }

    if ($tmpl) {
        # infos for our instrumentation comment
        my $url      = $tmpl->url;
        my $id       = $tmpl->template_id;
        my $json = qq[{type: "template", id: $id, filename: "$filename", url: "$url", cmsRoot: "$args{cms_root}"}];

        my $comment_start = "<!-- KrangPreviewFinder Start $json -->";
        my $comment_end   = "<!-- KrangPreviewFinder End $json -->";
        my $js_css_loader = $self->_get_preview_editor_js_css_loader(%args);

        # instrument the template
        push @$filters, sub {
            if (${$_[0]} =~ /<body[^>]*>/) {
                ${$_[0]} =~ s/(<body[^>]*>)/$1$comment_start/msi;
            } else {
                ${$_[0]} =~ s/(.*)/$comment_start$1/msi;
            }

            if (${$_[0]} =~ /<\/body[^>]*>/) {
                ${$_[0]} =~ s/(<\/body[^>]*>)/$comment_end$1$js_css_loader/msi;
            } else {
                ${$_[0]} =~ s/(.*)/$1$comment_end/msi
            };
        };

        #
        # additional instrumentation for SSIs (media)
        #
        my $tmpl_content = $tmpl->content;
        my %comment_for = ();

        # get virtual include paths and map it to start/end comments
        #               <!--#include virtual="the interesting part ending up in $2" --> 
        my $regexp = qr{<!--#include\s+virtual\s*=\s*(["'])([^"']+)\1\s*-->};
        while ($tmpl_content =~ /$regexp/gims) {
            my $path = $2;
            if (my ($ssi)    = pkg('Media')->find(url_like => "%$path")) {
                my $id       = $ssi->media_id;
                my $url      = $ssi->url;
                my $title    = $ssi->title;
                my $json     = qq[{type: "media", id: $id, title: "$title", url: "$url", cmsRoot: "$args{cms_root}"}];
                my $comment_start = "<!-- KrangPreviewFinder Start $json -->";
                my $comment_end   = "<!-- KrangPreviewFinder End $json -->";
                $comment_for{$path} = [$comment_start, $comment_end];
            }
        }

        # push the start/end comments in
        push @$filters, sub { ${$_[0]}
           =~ s/$regexp/$comment_for{$2}[0]$&$comment_for{$2}[1]/gims
        };

    }
}

#
# returns the the "Preview Finder" button with the JavaScript it needs
# to pull in the JavaScript needed by the preview finder feature.
#
sub _get_preview_editor_js_css_loader {
    my ($self, %args) = @_;

    return <<END;
<script type="text/javascript">
// pull in Preview Editor...
if (self != top) {
    // ... only if opened in its IFrame ...
    // ProtoPopup CSS
    var tpCSS = document.createElement('link');
    tpCSS.type="text/css";
    tpCSS.rel="stylesheet";
    tpCSS.href='$args{cms_root}/proto_popup/css/proto_popup.css';
    document.getElementsByTagName("head")[0].appendChild(tpCSS);

    // Preview Editor CSS
    var peCSS = document.createElement('link');
    peCSS.type="text/css";
    peCSS.rel="stylesheet";
    peCSS.href='$args{cms_root}/preview_editor/css/preview_editor.css';
    document.getElementsByTagName("head")[0].appendChild(peCSS);

    // Preview Editor JavaScript
    var tpScript = document.createElement('script');
    tpScript.setAttribute('language','JavaScript');
    tpScript.setAttribute('src','$args{cms_root}/js/preview_editor.js');
    document.body.appendChild(tpScript);
} else {
    // ... otherwise hide overlay
    try {
        document.getElementById('krang_preview_editor_top_overlay').style.display    = 'none';
        document.getElementById('krang_preview_editor_top_spacer').style.display     = 'none';

    } catch(er) {}
}

// hide the indicator initially
var ind = document.getElementById('krang_preview_editor_load_indicator');
if (ind) { ind.style.display = 'none' }
</script>
END
}

#
# Insert the Preview Editor's top overlay through a HTML::Template
# filter in category.tmpl
#
sub _insert_preview_editor_top_overlay {
    my ($self, %arg) = @_;

    my $title       = 'Krang Preview Editor';
    my $browse      = 'Browse';
    my $find_tmpl   = 'Find Template';
    my $edit        = 'Edit Story';
    my $steal       = 'Steal from';
    my $checked_out = 'Checked out by';
    my $close       = 'Close';
    my $help        = 'Help';
    my $loading     = 'Loading';
    my $forbidden   = 'No Edit Permission';

    my $help_url = $arg{cms_root} . "/help.pl?topic=preview_editor";

    my $indicator_css = "background-color: #cee7ff; color: #666; filter: alpha(opacity=90); opacity: .9; position: fixed; z-index: 32767; left: 0; bottom: 0; border: 1px solid #369; padding: 0.5em 0.6em; width: 70px; font-size: 9px; font-weight: bold; display: none";

    my $overlay =<<END;
<div id="krang_preview_editor_top_overlay" style="background: #cee7ff url($arg{cms_root}/images/bkg-button-mini.gif) repeat-x scroll 0 50%;"><div style="padding-top: 6px">
  <div id="krang_preview_editor_buttons_right"><a href="" id="krang_preview_editor_help" name="$help_url">$help</a><a href="" id="krang_preview_editor_close">$close</a></div>

  <span id="krang_preview_editor_logo">$title</span>

  <span id="krang_preview_editor_btn_browse"  class="krang_preview_editor_btn">$browse</span>
  <span id="krang_preview_editor_btn_find"    class="krang_preview_editor_btn" style="display:none">$find_tmpl</span>
  <span id="krang_preview_editor_btn_edit"    class="krang_preview_editor_btn" style="display:none">$edit</span>
  <span id="krang_preview_editor_btn_steal"   class="krang_preview_editor_btn" style="display:none">$steal</span>
  <span id="krang_preview_editor_checked_out" style="display:none">$checked_out</span>
  <span id="krang_preview_editor_forbidden"   style="display:none">$forbidden</span>

</div></div>

<div id="krang_preview_editor_load_indicator" style="$indicator_css">
<img alt="Load Indicator" src="$arg{cms_root}/images/indicator_small_bluebg.gif" style="padding 0 1em 0 0; vertical-align:middle">
<span id="krang_preview_editor_loading">$loading</span>&hellip;
</div>
END
        my $top_spacer = <<END;
<div id="krang_preview_editor_top_spacer"></div>
<div id="krang_preview_editor_messages" class="krang_preview_editor_slider" style="display:none;">
<div class="wrapper">
<div class="content" style="background: url('$arg{cms_root}/images/slider-info.gif') 20px 10px no-repeat;"></div>
<form>
<input value="$close" type="button" onclick="Krang.Messages.hide('messages')" class="krang_preview_editor_button" style="background: #EEE url('$arg{cms_root}/images/bkg-button-mini.gif') 0 50% repeat-x !important;"/>
</form>
</div></div>

<div id="krang_preview_editor_alerts" class="krang_preview_editor_slider" style="display:none;"><div class="wrapper">
<div class="content" style="background: url('$arg{cms_root}/images/slider-alert.gif') 20px 10px no-repeat;"></div>
<form>
<input value="$close" type="button" onclick="Krang.Messages.hide('alerts')" class="krang_preview_editor_button" style="background: #EEE url('$arg{cms_root}/images/bkg-button-mini.gif') 0 50% repeat-x !important;">
</form>
</div></div>
END

        push @{$arg{filters}}, sub { ${$_[0]} =~ s/(<body[^>]*>)/$1$top_spacer/msi };
        push @{$arg{filters}}, sub { ${$_[0]} =~ s/(<\/body[^>]*>)/$overlay$1/msi };
}

#
# return a DIV showing the element's display name for the Preview Editor overlay
#
sub _get_preview_editor_element_overlays {
    my ($self, %args) = @_;
    my $child = $args{child};

    # only the story's element is supported
    return '' unless $child and $child->object->isa('Krang::Story');

    my $path = $child ? $child->xpath : '/';
    my $id   = $args{publisher}->story->story_id;

    return qq{<div class="krang_preview_editor_element_label" name="{storyID: '$id', elementXPath: '$path'}" style="display: none">} . $child->display_name . '</div>';
}


=back

=head1 TODO

=over

=item *

Element classes should be able to control linked_stories and linked_media

=item *

Element deserializer should enforce min/max rules.


=item *

malformed element tree in category doesn't throw an error right

=item *

Krang::DataSet should check for element set mismatches since
Krang::Element is lazy now

=item *

deserialize_xml methods are trusting incoming urls, but they don't
actually use them...

=back

=cut

1;
