package Krang::Element;
use strict;
use warnings;

use Krang::ElementLibrary;
use Krang::ElementClass;
use Krang::DB qw(dbh);
use List::Util qw(first);
use Scalar::Util qw(weaken);
use Carp qw(croak);
use Carp::Assert qw(assert DEBUG);

# declare prototypes
sub foreach_element (&@);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(foreach_element);

=head1 NAME

Krang::Element - element data objectcs

=head1 SYNOPSIS

  use Krang::Element;

  # create a new top-level element
  my $element = Krang::Element->new(class => "article");

  # add a sub-element
  my $para = $element->add_child(class => "paragraph");

  # add data to the sub-element
  $para->data("some test data here");

  # get a reference to the parent of $para, aka $element
  $parent = $para->parent();

  # get a reference to the root element of this tree, also $element
  $root = $para->root();

  # another way to add a paragraph, this time in one step
  $element->add_child(class => "paragraph",
                      data  => "some test data here",
                     );

  # save the element to the database, cascading through children
  $element->save();

  # make some changes
  $element->add_child(class => "horizontal_rule");

  # make a copy of the element tree
  $copy = $element->clone();

  # loop through child elements, printing out data elements
  foreach ($element->children()) {
      print $_->display_name, " => ", $_->data, "\n";
  }

  # same thing, but recurses through children of children too
  use Krang::Element qw(foreach_element);
  foreach_element { 
      print $_->display_name, " => ", $_->data, "\n";
  } $element;

  # find a list of all paragraphs in the tree, using XPath-esque
  # notation
  @para = $element->match('//paragraph');

  # get the first paragraph of the second page
  ($para) = $element->match('/page[1]/paragraph[0]');

  # get a list of potential additional child classes, taking into
  # account max setting
  @classes = $element->available_child_classes();

  # load a top-level element by id
  $element1 = Krang::Element->load(element_id => 1);

  # delete it from the database
  $element1->delete();

=head1 DESCRIPTION

This module implements elements in Krang.  Krang elements belong to a
single element class, see L<Krang::ElementClass> for details.  Krang
elements exist to contain child elements and/or store data.  All
complex functionality, like C<burn()> and C<display_form()> is proxied
to the element class.

=head1 INTERFACE

=head2 METHODS

=over

=item C<< $element = Krang::Element->new(class => "article") >>

Creates a new element.  The 'class' parameter is required and may be
either the name of a top-level element class or a Krang::ElementClass
object.  Other options correspond to attribute methods below:

=over

=item element_id

=item data

=item children

=back

When an element is created, any child elements with 
C<< $child->class->min >> greater than one will be automatically created
as children of the new element.  This may be supressed by passing 
C<< no_expand => 1 >> to new(), but this should only be done from within 
this class.

=item C<< $element_id = $element->element_id() >>

Returns a unique ID for the element.  Will be C<undef> until after
the first C<save()>.

=cut

use Krang::MethodMaker
  new_with_init => 'new',
  new_hash_init => 'hash_init',
  get_set       => [ qw( element_id parent ) ],
  list          => [ qw( children ) ];  

# initialize a new object, creating children as required by the class
# unless no_expand is passed in
sub init {
    my $self = shift;
    my %args = @_;
    my $no_expand = delete $args{no_expand};

    # make sure we've got a class
    croak("Krang::Element->new() called without class parameter!")
      unless $args{class};

    # make sure we have a children array
    $args{children} ||= [];

    # delay loading data since it needs a fully initialized object to
    # call class->check_data
    my $have_data = exists $args{data};
    my $data = delete $args{data};

    # finish the object
    $self->hash_init(%args);

    # setup data, using default value if set
    $self->data($have_data ? $data : $self->{class}->default);

    # find children with min > 0 and create elements for them, unless
    # called from _load_tree, in which case no_expand will be passed
    # in
    unless ($no_expand) {
        my $min;
        foreach my $child_class ($self->{class}->children()) {
            $min = $child_class->min;
            if ($min > 0) {
                # add children of this class up to the minimum
                $self->add_child(class => $child_class) for (1 .. $min);
            }
        }
    }

    return $self;
}

=item C<< $class = $element->class() >>

An object descended from L<Krang::ElementClass> which controls the
functionality of the element.  You can set this with either the
C<name> of a top-level element class (ex. "article") or an object.
The return value is always an object.

B<NOTE:> Setting this after the object is created is not a good idea.

=cut

sub class {
    return $_[0]->{class} if (@_ == 1);
    my ($self, $val) = @_;

    # it's an element class object, store it
    return $self->{class} = $val 
      if ref $val and UNIVERSAL::isa($val, "Krang::ElementClass");

    # it's an element name, fetch it from the library
    return $self->{class} = Krang::ElementLibrary->top_level(name => $val);
}

=item C<< $element->data($data) >>

=item C<< $data = $element->data() >>

This scalar attribute contains the data associated with the element.
Depending on the element class it might be textual, numeric or even a
complex data structure.  To get a flattened representation, call
C<freeze_data()>.

=cut

sub data {
    return $_[0]->{data} if (@_ == 1);
    my ($self, $data) = @_;
    $self->check_data(data => $data);
    $self->{data} = $data;
    return $data;
}

=item C<< $parent = $element->parent() >>

Returns the parent element for this element, or C<undef> for the root
element.

=item C<< $root = $element->root() >>

Returns the root element for this element tree.

=cut

sub root {
    my $self = shift;
    return $self->{parent}->root()
      if defined $self->{parent};        
    return $self;
}

=item C<< $child = $element->add_child(class => "paragraph", %args) >>

=item C<< $child = $element->add_child(class => $class_obj, %args) >>

Create a new element object and add it as a child in the C<children>
list.  If called with a string then the class will be looked up in the
list of child classes for this element class.  An object may be
passed, in which case it must belong to the 
C<< $element->class->children >> list of element classes.

Extra C<%args> are passed along to C<< Krang::Element->new() >>
unchanged.

Returns the newly created child object.

=cut

sub add_child {
    my $self = shift;
    my %arg  = @_;
    my $children = $self->{children};

    unless (ref $arg{class}) {
        # lookup the child class in our class
        $arg{class} = $self->{class}->child($arg{class});
    }

    # enforce max, if set
    my $max = $arg{class}->max;
    if ($max) {
        my $name  = $arg{class}->name;
        my $count = 1;
        for (@$children) {
            $count++ if $_->class->name eq $name;
        }
        croak("Unable to add another '$name' to '" .
              $self->name . "' - max allowed is $max")
          if $count > $max;
    }

    # push on a weak reference to self as parent
    $arg{parent} = $self;
    weaken($arg{parent});

    # push on the child and return it
    push @$children, ref($self)->new(%arg);
    return ${$children}[-1];
}

=item C<< @children = $element->children() >>

Returns a list of child elements for this element.  These will be
Krang::Element objects.  For adding a new child, see 
C<< add_child() >>.

C<children> is a L<Krang::MethodMaker> list attribute.  Thus, the
following methods are available to manipulate the list of children:

=over

=item C<< @children = $element->children() >>

=item C<< $children_ref = $element->children() >>

=item C<< $element->children(@new_children) >>

=item C<< $element->children_push($child) >>

=item C<< $child = $element->children_pop() >>

=item C<< $child = $element->children_shift() >>

=item C<< $element->children_unshift($child) >>

=item C<< $element->children_splice($offset, $len, @new_children) >>

=item C<< $element->children_clean() >>

=item C<< $count = $element->children_count() >>

=item C<< $element->children_set(2 => $child2, 5 => $child5) >>

=back

=item C<< my $deck = $element->child('deck') >>

Find a child by class name.  If there are multiple children for this
class, returns the first one.  Croaks if a child of the specified
class does not exist.

=cut

sub child {
    my ($self, $name) = @_;
    my $child = first { $_->{class}->name eq $name } @{$self->{children}};
    return $child if $child;
    croak("Unable to find child of class '$name'.");
}

=item C<< $element->save() >>

Save the element, and all its children, to the database.  After this
call, C<element_id> is guaranteed to be filled in.  Should only be
called on top-level elements.

=cut

sub save {
    my $self = shift;
    my $dbh = dbh;

    # check top-levelitude
    croak("Unable to save() non-top-level element.")
      unless $self->{class}->top_level();

    if (defined $self->{element_id}) {
        # update data
        $dbh->do('UPDATE element SET data = ? WHERE element_id = ?', undef,
                 $self->freeze_data(), $self->{element_id});

        # loop through kids, calling _update_children()
        my @element_ids = $self->_update_children($self->{element_id});

        # remove deleted children, defined as elements with this
        # root_id but not in the list of elements just updated
        $dbh->do('DELETE FROM element WHERE root_id = ? 
                                            AND element_id NOT IN (' .
                 join(',', ("?") x @element_ids) . ')',
                 undef, $self->{element_id}, @element_ids);

    } else {
        # create new root and get the element_id
        $dbh->do('INSERT INTO element (class, data) VALUES (?,?)', undef,
                 $self->{class}->name, $self->freeze_data());
        $self->{element_id} = $dbh->{mysql_insertid};
        
        # update root_id (doesn't work in one statement)
        $dbh->do('UPDATE element SET root_id = element_id 
                  WHERE element_id = ?', undef, $self->{element_id});

        # loop through kids, calling _insert_children()
        $self->_insert_children($self->{element_id});
    }
}

# a stripped-down version of _update_children used with new element trees.
sub _insert_children {
    my ($self, $root_id) = @_;
    my $dbh = dbh;
    
    # insert children, numbering in order and remembering IDs
    my $ord = 1;
   
    foreach my $child (@{$self->{children}}) {
        # create a new element and get the ID
        $dbh->do('INSERT INTO element (parent_id, root_id, class, data, ord)
                  VALUES       (?,?,?,?,?)', undef,
                 $self->{element_id}, $root_id, $child->{class}->name, 
                 $child->freeze_data, $ord++);
        $child->{element_id} = $dbh->{mysql_insertid};

        # recurse, if needed
        $child->_insert_children($root_id)
          if @{$child->{children}};
    }
}

# update an existing element tree in place
sub _update_children {
    my ($self, $root_id) = @_;
    my $dbh = dbh;
    
    # insert children, numbering in order and remembering IDs
    my $ord = 1;
    my @element_ids = ($self->{element_id});
   
    foreach my $child (@{$self->{children}}) {
        if ($child->{element_id}) {
            # pre-existing child, update
            push(@element_ids, $child->{element_id});
           
            $dbh->do('UPDATE element SET data=?, ord=? WHERE element_id = ?',
                     undef, $child->freeze_data, $ord++, $child->{element_id});
        } else {
            # create a new element and get the ID
            $dbh->do(
                 'INSERT INTO element (parent_id, root_id, class, data, ord)
                  VALUES       (?,?,?,?,?)', undef,
                     $self->{element_id}, $root_id, $child->{class}->name, 
                     $child->freeze_data, $ord++);
            $child->{element_id} = $dbh->{mysql_insertid};
            
            push(@element_ids, $child->{element_id});
        }
        
        # recurse, if needed
        push(@element_ids, $child->_update_children($root_id))
             if @{$child->{children}};
    }

    return @element_ids;
}

=item C<< @classes = $element->available_child_classes() >>

Taking into account C<< $child->class->max >>, returns a list of
available child classes for new children.

=cut

sub available_child_classes {
    my $self = shift;
    my ($name, $max, %max);

    # find maximums
    foreach my $child_class ($self->{class}->children()) {
        $name = $child_class->name;
        $max  = $child_class->max;
        $max{$name} = $max == 0 ? ~0 : $max;
    }

    # loop through children, removing classes that have reached their max
    foreach my $child ($self->children()) {
        $name = $child->name;
        $max  = $child->max;
        assert(exists($max{$name})) if DEBUG;
        delete $max{$name} if --$max{$name} == 0;
    }

    return grep { exists $max{$_->name} } $self->{class}->children;
}

=item C<< $element = Krang::Element->load(element_id => $id) >>

Loads a Krang::Element object from the database.  This will only find
top-level elements and will load all child elements.

=cut

sub load {
    my $pkg  = shift;
    my %arg  = @_;
    my $dbh = dbh;

    if (exists $arg{element_id}) {
        # select all elements in this tree
        my $data = $dbh->selectall_arrayref(<<SQL, undef, $arg{element_id});
          SELECT   element_id, parent_id, class, data
          FROM     element
          WHERE    root_id = ?
          ORDER BY parent_id, ord
SQL
        croak("No element found matching id '$arg{element_id}'")
          unless $data and @$data;
       
        my $element;
        eval { $element = $pkg->_load_tree($data) };
        croak("Unable to load element tree with id '$arg{element_id}':\n$@")
          if $@;
        return $element;
    } 
   
    croak("Unrecognized load parameters: " .
          join(', ', map { "$_ => '$arg{$_}'" } keys %arg));
} 

# loads a tree from an array of element arrays coming from a
# selectall_arrayref on the element table, sorted by parent_id and
# ord columns.
use constant ELEMENT_ID => 0;
use constant PARENT_ID  => 1;
use constant CLASS      => 2;
use constant DATA       => 3;
sub _load_tree {
    my ($pkg, $data) = @_;

    # root must be first
    my $root = shift @$data;
    croak("first record is not a top-level element!")
      if defined $root->[PARENT_ID];

    # start out with the root
    my %ehash;
    $ehash{$root->[ELEMENT_ID]} =
      Krang::Element->new(element_id => $root->[ELEMENT_ID],
                          class      => $root->[CLASS],
                          no_expand  => 1
                         );
    # deserialize data
    $ehash{$root->[ELEMENT_ID]}->thaw_data(data => $root->[DATA]);


    # boom through children, since they're sorted on parent_id and
    # ord, the rows are guaranteed to contain no forward references
    # and to be in the correct order for calls to add_child()
    my $row;
    while (@$data) {
        $row = shift @$data;
        croak("found child '$row->[ELEMENT_ID]' with unknown parent ".
              "'$row->[PARENT_ID]'")
          unless (exists $ehash{$row->[PARENT_ID]});
        $ehash{$row->[ELEMENT_ID]} = 
          $ehash{$row->[PARENT_ID]}->add_child(class     => $row->[CLASS],
                                               element_id=> $row->[ELEMENT_ID],
                                               no_expand => 1
                                              );
        $ehash{$row->[ELEMENT_ID]}->thaw_data(data => $row->[DATA]);
    }

    # all done
    return $ehash{$root->[ELEMENT_ID]};
}

=item $element->delete()

=item Krang::Element->delete($element_id)

Delete the element, and all its children, from the database.  After
this call the element is empty, without children, data or an id.  This
call only works for top-level elements.  To remove elements from the
middle of a tree, simply remove them from the C<children> list in the
parent and then call C<save>.

Returns 1 on success.

=cut

sub delete {
    my $self = shift;
    my $dbh  = dbh;
    my $element_id;

    if (ref $self) {
        # check top-levelitude
        croak("Unable to save() non-top-level element.")
          unless $self->{class}->top_level();

        # check for ID 
        croak("Unable to delete() non-saved element.")    
          unless $self->{element_id}; $element_id = $self->{element_id};
    } else { $element_id = shift; }

    $dbh->do('DELETE FROM element WHERE root_id = ?', undef, 
             $element_id);

    # clear the object
    %{$self} = () if ref $self;

    return 1;
}

=item C<< $element_copy = $element->clone() >>

Creates a perfect copy of the element and all child elements.  This
includes C<element_id>s if available, which means that calling save()
on the returned element will overwrite the source element in the
database.

=cut

sub clone {
    my $self = shift;

    # start with a simple copy
    my $clone = bless({%$self}, ref($self));

    # clone children recursively
    $clone->{children} = [ map { $_->clone } @{$self->{children}} ];

    # fix up parent pointers
    for (@{$clone->{children}}) {
        $_->{parent} = $clone;
        weaken($_->{parent});
    }
    return $clone;
}

=item C<< foreach_element { print $_->name, "\n" } $element >>

Apply a block of code to each element in an element tree, recursing
down through the tree breadth first.  The subroutine is available for
export.

=cut

sub foreach_element (&@) {
    my $code = shift;
    while (@_) {
        $_ = shift;
        push(@_, $_->children);
        $code->();
    }
}

=item C<< $xpath = $element->xpath() >>

Get an xpath to uniquely identify this element.  Can be used with
match() to find the element later.  The xpath returned is guaranteed
to be unqiue within the element tree.  For example, the third
paragraph element inside the second page element has the xpath
"/page[1]/paragraph[2]".

This method is provided by L<Class::XPath>.  See the documentation for
that module for more details.

=item C<< ($para) = $element->match('/page[0]/paragraph[2]/' >>

=item C<< @paras = $element->match('//paragraph' >>

The match() method performs a search in the element tree using a
simplified XPath-esque notation.  This is useful for two purposes:

=over

=item 1 

To retrieve a single element based on a unique path.  For example, to
retrieve the second paragraph of the third page:

  ($para) = $element->match('/page[2]/paragraph[1]');

=item 2

To retrieve a set of elements that match a given criteria.  For
example, to get all the image captions regardless of where they exist
in the element tree:

  @captions = $element->match('//image/caption');

=back

This method is provided by L<Class::XPath>.  See the documentation for
that module for more details, including a full description of the
syntax supported by match().

=cut

# generate match() and xpath()
use Class::XPath   
  get_name => 'name',         # get the node name with the 'name' method
  get_parent => 'parent',     # get parent with the 'parent' method
  get_root   => 'root',       # call get_root($node) to get the root
  get_children => 'children', # get children with the 'kids' method

  get_attr_names => sub {},   # no attribs (yet?)
  get_attr_value => sub {},   # 
  get_content    => 'data',   # get content from the 'data' method
  ;

=back

=head2 PROXIED Krang::ElementClass METHODS

All L<Krang::ElementClass> methods are proxied to the C<class> object
for convenience, with the exception of C<children()> and C<child()>.  For
example, you can write:

  $display = $element->display_name();

Instead of the equivalent, but longer:

  $display = $element->class->display_name();

For methods which take an C<< element => $element >> parameter, this
paramter will be automatically filled in when called through the
proxied method.  For example, you can write:

  $element->input_form(query => $query);

Which is equivalent to:

  $element->class->input_form(element => $element,
                              query   => $query);

=cut

BEGIN {
    no strict 'refs'; # needed for glob assign
    
    foreach my $attr (qw( name
                          display_name
                          min
                          max
                          bulk_edit
                          required
                          reorderable
                          top_level
                          hidden
                          allow_delete
                          url_attributes
                        )) {
        *{"Krang::Element::$attr"} = sub { $_[0]->{class}->$attr() };
    }
    
    foreach my $meth (qw( input_form
                          burn 
                          validate
                          load_query_data
                          freeze_data 
                          is_container
                          thaw_data
                          build_url
                          param_names
                          view_data
                          bulk_edit_data
                          bulk_edit_filter
                          check_data
                        )) {
        *{"Krang::Element::$meth"} = 
          sub { 
              my $self = shift;
              $self->{class}->$meth(element => $self, @_) 
          };
    }
}

1;

=head1 TODO

=over

=item

Make $element->child('foo') and match('foo') faster than grepping
through $element->children() for 'foo'.  This probably means caching
the name to element mappings and updating them on changes to
children().  That's not easy to do and still allow children() to
return a reference that can be used to make changes.

=item

Do leak testing to make sure the use of weaken() here is having the
intended effect.

=item

Add STORABLE_freeze and STORABLE_thaw methods so that elements don't
serialize their class objects.  This causes much irratation while
doing element class development and will make element class upgrades
needlessly difficult.

=item

Add call to an element class method on delete to allow for cleanup of
external data.

=back

=cut

