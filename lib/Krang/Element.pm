package Krang::Element;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

# declare prototypes
sub foreach_element (&@);
our (@ISA, @EXPORT_OK);
BEGIN {
    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT_OK = qw(foreach_element);
}

use Krang::ClassLoader 'ElementLibrary';
use Krang::ClassLoader 'ElementClass';
use Krang::ClassLoader DB => qw(dbh);
use List::Util qw(first);
use Scalar::Util qw(weaken);
use Carp qw(croak);
use Krang::ClassLoader Log => qw(assert ASSERT debug info);
use Storable qw(nfreeze thaw);
use Krang::Cache;

=head1 NAME

Krang::Element - element data objects

=head1 SYNOPSIS

  use Krang::ClassLoader 'Element';

  # create a new top-level element, passing in the class name and
  # containing object
  my $element = pkg('Element')->new(class => "article", object => $story);

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
  use Krang::ClassLoader Element => qw(foreach_element);
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
  $element1 = pkg('Element')->load(element_id => 1, object => $story);

  # delete it from the database
  $element1->delete();

=head1 DESCRIPTION

This module implements elements in Krang.  Krang elements belong to a
single element class, see L<Krang::ElementClass> for details.  Krang
elements exist to contain child elements and/or store data.  All
complex functionality, like C<publish()> and C<display_form()>, is proxied
to the element class.

=head1 INTERFACE

=head2 METHODS

=over

=item C<< $element = Krang::Element->new(class => "article", object => $object) >>

Creates a new element.  The 'class' parameter is required and may be
either the name of a top-level element class or a Krang::ElementClass
object.  

The 'object' parameter is required for top-level elements and must
contain a reference to the object containing this element.

Other options correspond to attribute methods below:

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

use Krang::ClassLoader MethodMaker => 
  new_with_init => 'new',
  new_hash_init => 'hash_init',    
  get_set       => [ qw( element_id ) ];

sub id_meth { 'element_id' }

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
    $self->{children} = delete $args{children} || [];

    # delay loading data since it needs a fully initialized object to
    # call class->check_data
    my $have_data = exists $args{data};
    my $data = delete $args{data};

    # finish the object
    $self->hash_init(%args);

    # make sure we've got an object if this is a top_level
    croak("Krang::Element->new() called without object parameter!")
      if $self->class->isa('Krang::ElementClass::TopLevel') and
        not $self->object;

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
    return $self->{class} = pkg('ElementLibrary')->top_level(name => $val);
}

=item C<< $element->data($data) >>

=item C<< $data = $element->data() >>

This scalar attribute contains the data associated with the element.
Depending on the element class it might be textual, numeric or even a
complex data structure.  To get a flattened representation, call
C<freeze_data()>.

=cut

sub data {
    my ($self, $data) = @_;
    if (@_ == 1) {
        return $self->{data} unless $self->{_lazy_data};

        # thaw out lazy loaded data and return that
        $self->thaw_data(data => delete $self->{_lazy_data});
        return $self->{data};
    }    
    $self->check_data(data => $data);
    delete $self->{_lazy_data};
    return $self->{data} = $data;
}


=item C<< $object = $element->object() >>

Returns the object containing this element tree.  This will be either
a Krang::Story or a Krang::Category object.

=cut

sub object {
    my $self = shift;
    return $self->root->object(@_) if $self->parent;
    return $self->{object} unless @_;    
    $self->{object} = shift;
    
    # make sure not to create a circular reference
    weaken($self->{object});
}


=item C<< $object = $element->story() >>

Convenience method which returns $element->object() if
$element->object->isa('Krang::Story') and croaks otherwise.

=cut

sub story { 
    my $self = shift;
    my $object = $self->object;
    croak("Expected a pkg('Story') in element->object for $self->{element_id}, but didn't find on!")
      unless $object and $object->isa('Krang::Story');
    return $object;
}

=item C<< $object = $element->category() >>

Convenience method which returns $element->object() if
$element->object->isa('Krang::Category') and croaks otherwise.

=cut

sub category { 
    my $self = shift;
    my $object = $self->object;
    croak("Expected a pkg('Category') in element->object, but didn't find on!")
      unless $object and $object->isa('Krang::Category');
    return $object;
}

=item C<< $parent = $element->parent() >>

Returns the parent element for this element, or C<undef> for the root
element.

=cut

sub parent {
    my $self = shift;
    if (@_) {
        my $parent = shift;
        $self->{parent} = $parent;
        weaken($self->{parent});
    }
    return $self->{parent} ? $self->{parent} : undef;
}

=item C<< $root = $element->root() >>

Returns the root element for this element tree.

=cut

sub root {
    my $self = shift;
    return $self->{parent}->root()
      if $self->{parent};
    return $self;
}

=item C<< @children = $element->children() >>

Returns a list of child elements for this element.  These will be
Krang::Element objects.  For adding a new child, see C<< add_child() >>.
To delete a child from the list of children, see 
C<< remove_child() >>.  To reorder the list of children, use 
C<< reorder_children() >>.

=cut

sub children { 
    my $self = shift;
    croak("Illegal attempt to set children with children()!  Use add_child(), remove_children() or reorder_children() instead.")
      if @_;
    return @{$self->{children}};
}

=item C<< $count = $element->children_count() >>

Returns the number of children in the element.

=cut

sub children_count { return scalar @{shift->{children}} }

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

    # push on the child and return it
    push @$children, ref($self)->new(%arg, parent => $self);

    return ${$children}[-1];
}

=item C<< $element->remove_children(10, 20) >>

=item C<< $element->remove_children($child10, $child20) >>

This call removes children from the list of child elements.  You may
call it with either a list of indexes into the list of children, or
references to the children to be removed.  

Note that removing a child will alter the xpath()s of children in the
same class later in the list.  For example, removing the third page
('/page[2]') will cause '/page[3]' and '/page[4]' to become '/page[2]'
and '/page[3]'.

=cut

sub remove_children {
    my ($self, @list) = @_;
    my $children = $self->{children};

    # normalize to hash of indexes
    my %to_delete;
    foreach my $item (@list) {
        if (ref $item) {
            ($item) = grep { $children->[$_] == $item } (0 .. $#$children);
            croak("Unable to find matching child!") unless defined $item;
        }
        $to_delete{$item} = 1;
    }

    # process list
    my @new_children;
    for my $x (0 .. $#$children) {
        next if $to_delete{$x};
        push @new_children, $children->[$x];
    }

    # make the change
    @$children = @new_children;
}

=item C<< $element->reorder_children(0, 1, 2, 4, 3) >>

=item C<< $element->reorder_children($child1, $child2, $child4, $child3) >>

This call reorders the list of children.  You may pass either a list
of indexes (0 based) into the list of children or a list of child
objects.  You may not leave out any existing children in the list.

=cut

sub reorder_children {
    my $self = shift;
    my $children = $self->{children};

    # make sure list is unique
    my %seen;
    croak("reorder_children called with list containing duplicates: " . 
          join(',', @_))
      if grep { ++$seen{$_} != 1 } @_;

    # check size
    croak("reorder_children called with wrong sized list, or list containing ")
      unless @$children == @_;

    # normalize to a list of objects, in requested order
    foreach my $x (0 .. $#_) {
        $_[$x] = $children->[$_[$x]] unless ref $_[$x];
        croak("Unable to find matching child!") unless $_[$x];
    }

    # make the change
    @$children = @_;
}

=item C<< my $deck = $element->child('deck') >>

Find a child by class name.  If there are multiple children for this
class, returns the first one.  Returns C<undef> if a child of the
specified class does not exist.

=cut

sub child {
    my ($self, $name) = @_;
    return first { $_->{class}{name} eq $name } @{$self->{children}};
}

=item C<< $text = $element->child_data('deck') >>

Find a child by class name and returns its data.  If there are
multiple children for this class, uses the first one.  Returns
C<undef> if a child of the specified class does not exist.  This is
better than using C<< child('name')->data >> because it won't produce
an error if C<< child('name') >> doesn't exist.

=cut

sub child_data {
    my ($self, $name) = @_;
    my $child = first { $_->{class}{name} eq $name } @{$self->{children}};
    return undef unless $child;
    return $child->data;
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
      unless $self->{class}->isa('Krang::ElementClass::TopLevel');
    
    # saving with the cache on is verboten
    if (Krang::Cache::active()) {
        croak("Cannot save elements while cache is on!  This cache was started at " . join(', ', @{$Krang::Cache::CACHE_STACK[-1]}) . ".");
    }


    # call the save hook
    $self->{class}->save_hook(element => $self);

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

        # insert index data if needed
        if ($child->{class}->indexed) {
            foreach my $index_data ($child->index_data) {
                next unless defined $index_data;
                $dbh->do('INSERT INTO element_index (element_id, value) 
                          VALUES (?,?)', undef, 
                         $child->{element_id}, $index_data);
            }
        }

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
            # pre-existing child, replace (allows for reverting where
            # the element ID might be gone from the tree)
            $dbh->do(
                 'REPLACE INTO element (element_id, parent_id, root_id, 
                                        class, data, ord)
                  VALUES       (?,?,?,?,?,?)', undef,
                     $child->{element_id}, $self->{element_id}, $root_id, 
                     $child->{class}->name, $child->freeze_data, $ord++);

            # clear index data if needed
            $dbh->do('DELETE FROM element_index WHERE element_id = ?',
                     undef, $child->{element_id})
              if $child->{class}->indexed;

        } else {
            # create a new element and get the ID
            $dbh->do(
                 'INSERT INTO element (parent_id, root_id, class, data, ord)
                  VALUES       (?,?,?,?,?)', undef,
                     $self->{element_id}, $root_id, $child->{class}->name, 
                     $child->freeze_data, $ord++);
            $child->{element_id} = $dbh->{mysql_insertid};
        }
                    
        # insert index data if needed
        if ($child->{class}->indexed) {
            foreach my $index_data ($child->index_data) {
                next unless defined $index_data;
                $dbh->do('INSERT INTO element_index (element_id, value) 
                              VALUES (?,?)', undef, 
                         $child->{element_id}, $index_data);
            }
        }

        # remember this element_id
        push(@element_ids, $child->{element_id});
        
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
        assert(exists($max{$name})) if ASSERT;
        delete $max{$name} if --$max{$name} == 0;
    }

    return grep { exists $max{$_->name} } $self->{class}->children;
}

=item C<< $element = Krang::Element->load(element_id => $id, object => $object) >>

Loads a Krang::Element object from the database.  This will only find
top-level elements and will load all child elements.  The 'object'
parameter is required and must contain a reference to the object
containing this element.

=cut

sub load {
    my $pkg  = shift;
    my %arg  = @_;
    croak("Unrecognized load parameters: " .
          join(', ', map { "$_ => '$arg{$_}'" } keys %arg))
      unless $arg{element_id};

    my $dbh = dbh;

    # first look in the cache
    my $element = Krang::Cache::get('Krang::Element' => $arg{element_id});
    if ($element) {
        $element->object($arg{object}) unless $element->{object};
        return $element;
    }

    # select all elements in this tree
    my $data = $dbh->selectall_arrayref(<<SQL, undef, $arg{element_id});
          SELECT   element_id, parent_id, class, data
          FROM     element
          WHERE    root_id = ?
          ORDER BY parent_id, ord
SQL
    croak("No element found matching id '$arg{element_id}'")
      unless $data and @$data;
    
    
    eval { $element = $pkg->_load_tree($data, $arg{object}) };
    croak("Unable to load element tree with id '$arg{element_id}':\n$@")
      if $@;

    # set in the cache
    Krang::Cache::set('Krang::Element' => $arg{element_id} => $element);

    return $element;
} 

# loads a tree from an array of element arrays coming from a
# selectall_arrayref on the element table, sorted by parent_id and
# ord columns.
use constant ELEMENT_ID => 0;
use constant PARENT_ID  => 1;
use constant CLASS      => 2;
use constant DATA       => 3;
sub _load_tree {
    my ($pkg, $data, $object) = @_;

    # root must be first
    my $root = shift @$data;
    croak("first record is not a top-level element!")
      if defined $root->[PARENT_ID];

    # start out with the root
    my %ehash;
    $ehash{$root->[ELEMENT_ID]} =
      pkg('Element')->new(element_id => $root->[ELEMENT_ID],
                          class      => $root->[CLASS],
                          object     => $object,
                          no_expand  => 1,
                         );
    # deserialize data
    $ehash{$root->[ELEMENT_ID]}->thaw_data(data => $root->[DATA]);

    # boom through children, since they're sorted on parent_id and
    # ord, the rows are guaranteed to contain no forward references
    # and to be in the correct order for calls to add_child()
    my $row;
    while (@$data) {
        $row = shift @$data;
        
        # skip children with unloaded parents, since they probably
        # failed to find an element class.  At some point we might
        # want to differentiate between this case and pure database
        # corruption.
        next unless exists $ehash{$row->[PARENT_ID]};

        eval { 
            $ehash{$row->[ELEMENT_ID]} = 
              $ehash{$row->[PARENT_ID]}->add_child(class     => $row->[CLASS],
                                                   element_id=> $row->[ELEMENT_ID],
                                                   no_expand => 1
                                                  );

            if ($ehash{$row->[ELEMENT_ID]}->lazy_loaded) {
                # store data for later loading
                $ehash{$row->[ELEMENT_ID]}->{_lazy_data} = $row->[DATA];
            } else {
                $ehash{$row->[ELEMENT_ID]}->thaw_data(data => $row->[DATA]);
            }
            
        };
        if ($@ and $@ =~ /No class named/) {
            # this is the result of a missing class definition,
            # issue a warning and move on
            info("Unable to load data for element class '$row->[CLASS]' - there is no matching definition in this element set.");
            next;
        } elsif ($@ and $@ =~ /Unable to add another/) {
            # the incoming XML has too many of something.  Make this
            # non-fatal to ease the transition from one element schema
            # to another.
            info("Unable to load data for element class '$row->[CLASS]' - unable to add another to parent element.");
            next;
        } elsif ($@) {
            die $@; 
        } 
    }

    # all done
    return $ehash{$root->[ELEMENT_ID]};
}

=item $element->delete()

Delete the element, and all its children, from the database.  After
this call the element is empty, without children, data or an id.  This
call only works for top-level elements.  To remove elements from the
middle of a tree, simply remove them from the C<children> list in the
parent and then call C<save>.

=cut

sub delete {
    my ($self, %args) = @_;
    my $dbh  = dbh;

    # check top-levelitude
    croak("Unable to delete() non-top-level element.")
      unless $self->{class}->isa('Krang::ElementClass::TopLevel');

    # check for ID 
    croak("Unable to delete() non-saved element.")    
      unless $self->{element_id};

    # call delete hook in the element class, unless it shouldn't run
    # now (as in story or category import)
    $self->class->delete_hook(element => $self)
      unless $args{skip_delete_hook};

    # delete all from the DB
    foreach_element {
        $dbh->do('DELETE FROM element_index WHERE element_id = ?', 
                 undef, $_->{element_id})
    } $self;
    $dbh->do('DELETE FROM element WHERE root_id = ?', undef, 
             $self->{element_id});

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
        $_->parent($clone);
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
        local $_ = shift;
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

  get_attr_names => '_xpath_attr_names',  # get attr names
  get_attr_value => '_xpath_attr_value', # get attr values
  get_content    => 'data',   # get content from the 'data' method
  ;

sub _xpath_attr_names {
    my $self = shift;
    return (keys(%{$self}), keys(%{$self->{class}}));
}

sub _xpath_attr_value {
    my ($self, $attr) = @_;
    return $self->$attr() if $self->can($attr);
    return undef;    
}

=item C<< $element->serialize_xml(writer => $writer, set => $set) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self, %arg) = @_;
    my ($writer, $set) = @arg{qw(writer set)};

    $writer->startTag('element');    
    $writer->dataElement(class => $self->name());
    $self->freeze_data_xml(writer => $writer, set => $set);
    foreach my $child ($self->children) {
        $child->serialize_xml(writer  => $writer,
                              set     => $set);
    }
    $writer->endTag('element');
}

=item C<< $element = Krang::Element->deserialize_xml(data => $data, set => $set, no_update => 0, object => $story) >>

Deserialize XML.  See Krang::DataSet for details.  This method differs
only in that it takes a reference to the element data produced by
XML::Simple rather than XML source.  Also takes an object parameter
pointing to the enclosing object.

=cut

sub deserialize_xml {
    my ($pkg, %args) = @_;
    my ($data, $set, $object) = 
      @args{qw(data set object)};

    # create the root element
    my $root = pkg('Element')->new(class     => $data->{class},
                                   object    => $object,
                                   no_expand => 1);
    $root->thaw_data_xml(data => $data->{data},
                         set  => $set);

    # recursively expand children
    if ($data->{element}) {
        $root->_deserialize_xml_children(data   => $data,
                                         set    => $set);
    }

    return $root;
}

# recursively expand children from XML data
sub _deserialize_xml_children {
    my ($self, %args) = @_;
    my ($data, $set) =  @args{qw(data set)};

    foreach my $child_data (@{$data->{element}}) {
        eval { 
            # create child
            $self->add_child(class     => $child_data->{class},
                             no_expand => 1);
            # thaw child data
            $self->{children}[-1]->thaw_data_xml(data => $child_data->{data},
                                                 set  => $set);
        };
        if ($@ and $@ =~ /No class named/) {
            # this is the result of a missing class definition,
            # issue a warning and move on
            info("Unable to load data for element class '$child_data->{class}' - there is no matching definition in this element set.");
            next;
        } elsif ($@ and $@ =~ /Unable to add another/) {
            # the incoming XML has too many of something.  Make this
            # non-fatal to ease the transition from one element schema
            # to another.
            info("Unable to load data for element class '$child_data->{class}' - unable to add another to parent element.");
            next;
        } elsif ($@) {
            die $@; 
        } else {
            # recurse if needed
            if ($child_data->{element}) {
                $self->{children}[-1]->_deserialize_xml_children(data => 
                                                                 $child_data,
                                                                 set  => $set);
            }
        }
    }
}


# freeze element tree as a flattened array
sub STORABLE_freeze {
    my ($self, $cloning) = @_;
    return if $cloning;

    # build packed array of element data
    my %ref_to_index;
    my $i = 0;
    my @data;
    $self->_freeze_tree(0, \@data);

    # freeze it
    my $data;
    eval { $data = nfreeze(\@data) };
    croak("Unable to freeze element: $@") if $@;

    return $data;
}

# recursively freeze elements
sub _freeze_tree {
    my ($self, $parent_at, $data) = @_;
    push @$data, [ $self->{element_id},
                   $parent_at,
                   $self->name,
                   $self->freeze_data, 
                 ];          

    $parent_at = $#$data;
    foreach my $child ($self->children) {
        $child->_freeze_tree($parent_at, $data);
    }
}

        
# thaw the frozen element array
sub STORABLE_thaw {
    my ($self, $cloning, $frozen) = @_;

    # FIX: is there a better way to do this?
    # Krang::Element::STORABLE_thaw needs a reference to the story in
    # order to thaw the element tree, but thaw() doesn't let you pass
    # extra arguments.
    our $THAWING_OBJECT;

    # retrieve data stack
    my @data;
    eval { @data = @{thaw($frozen)} };
    croak("Unable to thaw element: $@") if $@;

    # thaw out the root
    my $root =  pkg('Element')->new(element_id => $data[0][0],
                                    class      => $data[0][2],
                                    object     => $THAWING_OBJECT,
                                    no_expand  => 1,
                                   );
    $root->thaw_data(data => $data[0][3]);

    # copy into $self
    %$self = %{$root};

    # copy it into location 0 so kids can find it
    $data[0] = $self;

    # boom through children, since they're guaranteed to contain no
    # forward references and to be in the correct order for calls to
    # add_child()
    for my $i (1 .. $#data) {
        # all rows should have parent pointers
        assert(defined($data[$i][1])) if ASSERT;
        my $element = 
          $data[$data[$i][1]]->add_child(element_id => $data[$i][0],
                                         class      => $data[$i][2],
                                         no_expand => 1
                                        );
        $element->thaw_data(data => $data[$i][3]);
        $data[$i] = $element;
    }
}

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
                          hidden
                          allow_delete
                          url_attributes
                          pageable
                          indexed
                          lazy_loaded
                        )) {
        *{"Krang::Element::$attr"} = sub { $_[0]->{class}->$attr() };
    }
    
    foreach my $meth (qw( input_form
                          burn 
                          validate
                          validate_children
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
                          default_schedules
                          freeze_data_xml
                          thaw_data_xml
                          template_data
                          publish
                          fill_template
                          index_data
                          publish_check
                          force_republish
                          use_category_templates
                          mark_form_invalid
                        )) {
        *{"Krang::Element::$meth"} = 
          sub { 
              my $self = shift;
              $self->{class}->$meth(@_, element => $self) 
          };
    }
}

1;

=head1 TODO

=over

=item *

Make $element->child('foo') and match('foo') faster than grepping
through $element->children() for 'foo'.  This probably means caching
the name to element mappings and updating them on changes to
children().  That's not easy to do and still allow children() to
return a reference that can be used to make changes.

=back

=cut

