package Krang::ElementClass;
use strict;
use warnings;

use Carp qw(croak);
use CGI ();

use HTML::Template::Expr;
use Krang::Log qw(debug info critical);

use Krang::Pref;

use Exception::Class
  'Krang::ElementClass::TemplateNotFound' => { fields => [ 'element_name', 'template_name', 'category_url', 'error_msg' ] },
  'Krang::ElementClass::TemplateParseError' => {fields => [ 'element_name', 'template_name', 'category_url', 'error_msg' ] };

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
                         hidden
                         allow_delete
                         default
                         pageable
                         indexed
                         lazy_loaded
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
            croak("Unable to add child named '$arg->{name}' to $self->{name}: there is already a child with that name.")
              if exists $children_by_name{$arg->{name}};
            $children_by_name{$arg->{name}} = $arg;
        } else {
            # it's the name of an element, load it
            my $class = Krang::ElementLibrary->find_class(name => $arg);
            croak("Unable to find element class named '$arg' while instantiating '$self->{name}'.")
              unless $class;
            croak("Unable to add child named '$arg' to $self->{name}: there is already a child with that name.")
              if exists $children_by_name{$arg};
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
    
    return scalar $query->hidden(-name     => $param,
                                 -default  => ($element->data() || ""),
                                 -override => 1);
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

=item C<< ($bool, $msg) = $class->validate_children(element => $element, query => $query) >>

Given the CGI.pm query object from a form submission, this call must
return true of the input is valid for the elements children, taken
collectively and false if not.  If false, an error message should be
returned as well, describing the error.  This method is only called if
all the children return (1) from their validate methods.

The default implementation does nothing.

=cut

sub validate_children { 
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

This attribute returns the data associated with the element, formatted
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
    my $element   = $args{element};
    my $filename  = $args{filename};

    croak __PACKAGE__ . ":missing attribute 'element' or 'filename'.\n" if (not $element and not $filename);

    my @search_path = $publisher->template_search_path();
    $filename = $element->name() . '.tmpl' if not $filename;

    # this is needed so that element templates don't get Krang's templates
    local $ENV{HTML_TEMPLATE_ROOT} = "";

    # Attempt to instantiate an HTML::Template::Expr object with that
    # as the search path.
    my $template;
    eval {
        $template = HTML::Template::Expr->new(filename          => $filename,
                                              path              => \@search_path,
                                              die_on_bad_params => 0,
                                              loop_context_vars => 1,
                                              global_vars       => 1,
                                              cache             => 1,
                                              search_path_on_include => 1,
                                              %args,
                                             );
    };

    if ($@) {
        my $err = $@;
        # HTML::Template::Expr is having problems - throw an error
        # based on the problem reported.
        if ($err =~ /file not found/) {
            Krang::ElementClass::TemplateNotFound->throw
                (
                 message       => "Missing required output template: '$err'",
                 element_name  => ($element ? $element->display_name() : $filename),
                 template_name => $filename,
                 category_url  => $publisher->category->url(),
                 error_msg     => $err
                );
        }
        # assuming remaining errors are parse errors at this time.
        else {
            # parse the message - stack traces aren't user-friendly.
            $err =~ /^(.+?)\n[^\n]+Template\:\:Expr/so;
            my $msg = $1;

            Krang::ElementClass::TemplateParseError->throw
                (
                 message       => "Coding error found in template: '$msg'",
                 element_name  =>  ($element ? $element->display_name() : $filename),
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
is responsible for populating the otuput template of the element with
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

A single variable called C<< $child->name() >> is created for each 
B<UNIQUELY NAMED> child element.  For example, if the element contains 
children named (C<paragraph>, C<paragraph>, C<deck>), two variables 
would be created, C<paragraph> and C<deck>.  The value of C<paragraph> 
would correspond to the first paragraph child element.

=item * 

A loop is created for every child element named with the name of the
element followed by _loop. The rows of the loop contain the variable
described above and a _count variable.

=item * 

A loop called C<element_loop> is created with a row for every child
element contained. The values are the same as for the loop above with
the addition of a boolean is_ variable.

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

A variable called C<page_break> containing C<< Krang::Publisher->page_break() >>

=back

B<NOTE:> If you're developing your own elements, be aware that there exists the potential for naming collisions.  For example, if you create a child element named C<title>, you create a collsion with C<< $story->title >>.  Default behavior is that element children take precedence over everything else in a naming collision.  Avoid this by choosing better names for your elements.

=cut

sub fill_template {

    my $self = shift;
    my %args = @_;

    my $tmpl      = $args{tmpl};
    my $publisher = $args{publisher};
    my $element   = $args{element};

    my $story     = $publisher->story();

    my @element_children = $element->children();

    # list of variable names in the template -- add element_loop vars if needed
    my %template_vars = map { $_ => 1 } $tmpl->query();
    if (exists($template_vars{element_loop})) {
        delete $template_vars{element_loop};
        foreach ($tmpl->query(loop => 'element_loop')) {
            $template_vars{element_loop}{$_} = 1;
        }
    }


    # list of child element names that have been seen
    my %element_names = ();

    # build out params going to the template.
    my %params  = (
                   $element->name() => $element->template_data(publisher => $publisher),
                   $element->name() . '_total' => scalar(@element_children)
                  );


    # add story title, cover date, page break, and content-break tags, if needed.
    $params{title} = $publisher->story()->title()
      if exists($template_vars{title});

    $params{cover_date} = $publisher->story()->cover_date()->strftime('%b %e, %Y %l:%M %p') if exists($template_vars{cover_date});

    $params{page_break} = $publisher->page_break()
      if exists($template_vars{page_break});

    $params{content} = $publisher->content()
      if (exists($template_vars{content}) && $element->name() eq 'category');

    # add the contributors loop if desired
    $params{contrib_loop} = $self->_build_contrib_loop(@_)
      if exists($template_vars{contrib_loop});


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
            push @page_urls, $self->_build_page_url(page => $count,
                                                    publisher => $publisher);
        }
    }


    my %element_count;
    my %child_params;

    foreach my $child (@element_children) {
        my $name     = $child->name;
        my $loopname = $name . '_loop';
        my $html;
        my %fill_template_args;

        # skip this child unless something in the template references
        # it!  e.g. it exists in element loop, a name_loop, or
        # directly in the template, not seen before.
        next unless (exists($template_vars{element_loop}{$name}) || 
                     exists($template_vars{element_loop}{"is_$name"}) ||
                     exists($template_vars{$loopname}) ||
                     (exists($template_vars{$name}) && !exists($child_params{$name})));

        # Pass pagination variables along to child->publish if the
        # child element is pageable (e.g. is used for determining what
        # constitutes a page).
        if ($child->pageable) {
            my $pagination_info = $self->_build_pagination_vars(page_list => \@page_urls,
                                                                page_num => $page_number++);

            map { $fill_template_args{$_} = $pagination_info->{$_} } keys %{$pagination_info};

        }

        # build element_loop if it exists.
        if (exists($template_vars{element_loop}{$name})) {
            # get html for element
            $html = $child->publish(publisher => $publisher, 
                                    fill_template_args =>\%fill_template_args);

            $element_count{$name} ? $element_count{$name}++ : ($element_count{$name} = 1);
            push @{$child_params{element_loop}}, {
                                            "is_$name" => 1,
                                            $name      => $html,
                                            $name.'_count' => $element_count{$name}
                                           };
        }

        # does '$name_loop' exist?  build it.
        if (exists($template_vars{$loopname})) {
            # get html for element, unless it's already built
            $html ||= $child->publish(publisher => $publisher, 
                                      fill_template_args =>
                                      \%fill_template_args);

            my $loop_idx = 1;
            if (exists($child_params{$loopname})) {
                $loop_idx = @{$child_params{$loopname}} + 1;
            }
            my %loop_entry = ($name . '_count' => $loop_idx,
                              $name            => $html,
                              "is_$name"       => 1);

            # fix to make contrib_loop available - this is because
            # HTML::Template does not support global loops - only global_vars
            if ($tmpl->query(name => [$loopname,'contrib_loop'])) {
                $child_params{contrib_loop} = $self->_build_contrib_loop(@_) unless
                  exists($child_params{contrib_loop});
                $loop_entry{contrib_loop} = $child_params{contrib_loop};
            }

            push @{$child_params{$loopname}}, \%loop_entry;

        }

        # if the element is used in the template outside of a loop,
        # and hasn't been set (first child element takes precedence),
        # do it.
        if (exists($template_vars{$name}) && !exists($child_params{$name})) {
            # get html for element, unless it's already built
            $html ||= $child->publish(publisher => $publisher, 
                                      fill_template_args =>
                                      \%fill_template_args);
            $child_params{$name} = $html;
        }
    }


    $tmpl->param(%params, %child_params);
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
children, however, publish() will propegate the error thrown by
find_template().


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
    my $element_id = $args{element}->element_id();

    # try and find an appropriate template.
    eval { $html_template = $self->find_template(@_); };

    if (my $err = $@) {
        if ($err->isa('Krang::ElementClass::TemplateNotFound')) {
            # no template found - if the element has children, this is an error.
            # otherwise, return the raw data stored in the element.
            if (scalar($args{element}->children())) {
                die $err;
            } else {
                return $args{element}->template_data(publisher => $publisher);
            }
        } else {
            # another error occured with the template - re-throw.
            die $err;
        }
    }

    $self->fill_template(tmpl => $html_template, @_);
    my $html;

    # make sure publish returns cleanly
    eval { $html = $html_template->output(); };

    if (my $err = $@) {
        # known output problems involve bad HTML::Template::Expr usage.
        if ($err =~ /HTML::Template::Expr/) {
            # try and parse $err to remove the stack trace.
            $err =~ /^(.*?Expr.*?\n)/so;
            my $msg = $1;

            Krang::ElementClass::TemplateParseError->throw
                (
                 message       => "Error publishing with template: '$msg'",
                 element_name  => $args{element}->display_name,
                 template_name => $args{element}->name . '.tmpl',
                 category_url  => $publisher->category->url(),
                 error_msg     => $err
                );
        } else {
            die $err;
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
    my ($self, %arg) = @_;
    my ($element, $writer) = @arg{qw(element writer)};
    
    my $data = $element->freeze_data();
    $writer->dataElement(data => 
                         (defined $data and length $data) ? $data : '');
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
    my ($self, %arg) = @_;
    my ($element, $data) = @arg{qw(element data)};
    $self->thaw_data(element => $element, data => $data->[0]);
}


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
    $args{min}          = 0  unless exists $args{min};
    $args{max}          = 0  unless exists $args{max};
    $args{bulk_edit}    = 0  unless exists $args{bulk_edit};
    $args{required}     = 0  unless exists $args{required};
    $args{children}     = [] unless exists $args{children};
    $args{hidden}       = 0  unless exists $args{hidden};
    $args{reorderable}  = 1  unless exists $args{reorderable};
    $args{allow_delete} = 1  unless exists $args{allow_delete};
    $args{default}      = undef  unless exists $args{default};
    $args{indexed}      = 0 unless exists $args{indexed};
    $args{lazy_loaded}  = 0 unless exists $args{lazy_loaded};

    # call generated inititalizer
    $self->hash_init(%args);

    return $self;
}


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

    my $page_num  = $args{page} || 0;
    my $publisher = $args{publisher} || $self->{publisher};
    my $protocol  = $args{protocol} || 'http://';

    my $story     = $publisher->story;

    my $base_url;

    if ($publisher->is_publish) {
        $base_url = $story->url();
    } elsif ($publisher->is_preview) {
        $base_url = $story->preview_url();
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

    if ($page_num == 1) { # on the first page
        $page_info{is_first_page}     = 1;
        $page_info{previous_page_url} = '';
    } else {
        $page_info{is_first_page}     = 0;
        $page_info{previous_page_url} = $page_list->[($current_idx - 1)];
    }

    if ($page_num == @$page_list) { # on the last page
        $page_info{is_last_page}  = 1;
        $page_info{next_page_url} = '';
    } else {
        $page_info{is_last_page}  = 0;
        $page_info{next_page_url} = $page_list->[($current_idx + 1)];
    }

    for (my $num = 0; $num <= $#$page_list; $num++) {
        my %element = (page_number => ( $num + 1 ),
                       page_url    => $page_list->[$num]);

        ($num == $current_idx) ? ( $element{is_current_page} = 1 ) :
          ( $element{is_current_page} = 0 );

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

    my $object   = $args{element}->object;
    my $base_cat = $object->isa('Krang::Story') ? $object->category : $object;

    push (@category_loop, { display_name => $base_cat->element->child('display_name')->data, url => $base_cat->url } );

    while ( $base_cat->parent ) {
        $base_cat = $base_cat->parent;
        unshift (@category_loop, { display_name => $base_cat->element->child('display_name')->data, url => $base_cat->url } );
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

    my %contrib_types = Krang::Pref->get('contrib_type');

    my %contribs = ();
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
        push @{$contribs{$cid}{contrib_type_loop}}, {contrib_type_id => $contrib_type_id,
                                                     contrib_type_name => $contrib_types{$contrib_type_id}};

    }

    foreach my $contrib_id (@contrib_order) {
        push @contributors, $contribs{$contrib_id};
    }

    return \@contributors;
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
