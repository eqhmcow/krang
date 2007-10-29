package Krang::ElementClass::ListGroup;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass::Storable';
use Krang::ClassLoader Log => qw(debug info);
use Krang::ClassLoader 'ListGroup';
use Krang::ClassLoader 'List';
use Krang::ClassLoader 'ListItem';

use Carp qw(croak);

use Krang::ClassLoader MethodMaker => 
  get_set => [ qw( size multiple list_group ) ];

sub new {
    my $pkg = shift;
    my %args = ( size      => 5,
                 multiple  => 0,
                 list_group    => '',
                 @_
               );

    return $pkg->SUPER::new(%args);
}

sub check_data {
    my ($class, %arg) = @_;
    croak("ListGroup element class requires an array-ref in data().")
      unless not defined $arg{data} or 
        (ref($arg{data}) and ref($arg{data}) eq 'ARRAY');
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $jparam;

    my ($lg) = pkg('ListGroup')->find( name => $self->list_group() );

    my ($all_pulldowns, $html_output);

    # iterate over the lists in this listgroup, building scrolling
    # lists for each one.
    my $list_index = 0;

    my @lists = pkg('List')->find( list_group_id => $lg->list_group_id );

    my $element_data = $element->data();

    if ($#lists > 0) {
        # if there is more than one list (e.g. multidimensional), need
        # to use javascript to manage everything.

        my $root_list = $lists[0];

        # turn param into something unique that can be used as a
        # javascript identifier
        ($jparam = $param) =~ s/\W//g;

        # put all list items into a javascript tree, indexed by list id

        # start by serializing all list data
        $html_output = <<END;
<script type="text/javascript">
  // JavaScript to manage listgroup $jparam
  var ${jparam}_data = new Array();
  var ${jparam}_index = new Array();
END

        # grab the list of items for the first list in the listgroup:
        my $x = 0;
        my @root_items = pkg('ListItem')->find( list_id => $root_list->list_id,
                                                no_parent => 1,
                                              );
        foreach my $item (@root_items) {
            $self->_add_item(\$html_output, $item, "${jparam}_data[$x]", $jparam);
            $x++;
        }


        # setup function to update lists
        $html_output .= <<END;

function ${jparam}_update( e, which ) {
   var i = e.selectedIndex;
   if (i < 0) return;
   var list_item_id = e.options[i].value;

   // find target list and empty it
   var target = document.getElementById("${param}_" + (which + 1));
   if (!target) {
      // alert("Couldn't find " + "${param}_" + (which + 1));
      return;
   }
   target.options.length = 0;

   // find item index in tree
   var item = ${jparam}_index[list_item_id];
   if (!item) return;

   // replace next list down with sub items
   var sub = item["sub"];
   for (var x = 0; x < sub.length; x++) {
       target.options[x] = new Option(sub[x]["data"], sub[x]["id"],
                                      false, false);
   }

   // zap last list if this is first
   if (which == 0) {
     var targ = document.getElementById("${param}_" + (which + 2));
     if (!targ) return;
     targ.options.length = 0;
   }

}

</script>
END
        ;

    }



    foreach my $list (@lists) {
        # now iterate over the lists, building out everything.

        my (@items, @values, %labels);

        my $list_param = $param . '_' . $list_index;

        my %params = (-name    => $list_param,
                      -size    => $self->size(),
                      -default => ($self->multiple ?
                                   ($element->data || []) :
                                   (($element->data && $element->data->[$list_index]) || ""))
                     );

        # only populate scrolling listbox for the first list - the
        # rest will be done w/ javascript.

        my %find_params = (list_id => $list->list_id);
        $find_params{parent_list_item_id} = $element->data()->[($list_index - 1)] 
          if ($list_index && $element->data());

        @items = pkg('ListItem')->find( %find_params );

        @values = map { $_->list_item_id } @items;
        %labels = map { $_->list_item_id => $_->data } @items;

        if ($self->multiple) {
            $params{-multiple} = 'true';
        }

        $params{-values}  = \@values;
        $params{-labels}  = \%labels;

        # make the jscript call if it is multidimensional
        if ($#lists > 0) {
            $params{-onclick}  = "${jparam}_update(this, $list_index);";
            $params{-onkeyup}  = "${jparam}_update(this, $list_index);";
        }

        my $pulldown = scalar $query->scrolling_list(%params);

        $pulldown =~ s!<select!<select id="${param}_${list_index}"!i;

        if ($#lists > 1) {
            $all_pulldowns .= sprintf( "<strong>%s</strong><BR>\n%s<BR>\n",
                                       $list->name, $pulldown );
        } else {
            $all_pulldowns .= sprintf( "%s",
                                       $pulldown );
        }

        $list_index++;
    }

    $html_output .= $all_pulldowns;

    return $html_output;
}

#
# _add_item is used to build out the javascript array for multidimensional lists.
#
sub _add_item {
    my $self = shift;
    my ($html, $item, $pre, $jparam, $stop) = @_;
    my $id = $item->list_item_id;
    my $data = $item->data;
    $data =~ s!\\!\\\\!g;
    $data =~ s!"!\\"!g;
    $$html .= "$pre = new Array();\n";
    $$html .= $pre . qq{["id"] = $id;\n};
    $$html .= $pre . qq{["data"] = "$data";\n};
    $$html .= qq{${jparam}_index["$id"] = $pre;\n};

    # collect sub-items.  Iterate and recursively build further.
    my @sub_items = pkg('ListItem')->find(parent_list_item_id => $id);
    if (@sub_items) {
        my $x = -1;
        $$html .= $pre. qq{["sub"] = new Array();\n};
        foreach my $item (@sub_items) {
            $x++;
            $self->_add_item($html, $item, $pre . qq{["sub"][$x]}, $jparam, ($stop || 0) + 1);
        }
    } else {
        $$html .= $pre . qq{["sub"] = [];\n};
    }
}


# param name is based on xpath & the field index

sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $param = $element->xpath;

    my @data;
    my $i = 0;

    my $q_param = $param . "_" . $i++;
    while (defined($query->param($q_param))) {
        push @data, $query->param($q_param);
        $q_param = $param . "_" . $i++;
    }

    $element->data(\@data);
}

sub template_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    return "" unless $element->data;

    my @chosen;
    foreach my $e (@{$element->data}) {
        my $i = (pkg('ListItem')->find( list_item_id => $e ))[0] || '';
        push(@chosen, $i->data) if $i;
    }
    return join(', ', @chosen);
}

# Customized to look for array content in Nth list
sub validate { 
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    # Find Nth list
    my $i = 0;
    while (defined($query->param($param."_".$i))) {
        # Look for next param
        $i++;
    }
    my $nth_list_param = $param . "_" . ($i-1);
    my @values = $query->param($nth_list_param);

    if ($self->{required} and (not scalar(@values))) {
        return (0, "List $self->{display_name} requires a value.");
    }
    return 1;
}

sub view_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    return "" unless $element->data;

    my @chosen; 
    foreach my $e (@{$element->data}) {
        my $i = (pkg('ListItem')->find( list_item_id => $e ))[0] || '';
        push(@chosen, $i->data) if $i;
    }
    return join("<br>", @chosen);
}


# Add ListItems to DataSet.  Remove listitems which no longer exist
sub freeze_data_xml {
    my ($self, %arg) = @_;
    my ($element, $writer, $set) = @arg{qw(element writer set)};

    my $element_data = $element->data();

    # Iterate through data, add to KDS, and remove if the item doesn't exist anymore.
    my @real_element_data = ();
    foreach my $list_item_id (@$element_data) {
        my ($li) = pkg('ListItem')->find(list_item_id => $list_item_id);
        unless ($li) {
            info ("Can't find list item for list_item_id '$list_item_id'.  Dropping it from KDS.");
            next;
        }
        my $element_id = $element->element_id();
        debug ("Adding list_item_id '$list_item_id' associated with element_id '$element_id' to KDS");
        $set->add(object => $li, from => $element->object);
        push(@real_element_data, $list_item_id); # Only valid list_item_ids
    }

    # Update element data and export
    $element->data(\@real_element_data);
    my $data = $element->freeze_data();
    $writer->dataElement(data => 
                         (defined $data and length $data) ? $data : '');
}


# Map to incoming ListItems
sub thaw_data_xml {
    my ($self, %arg) = @_;
    my ($element, $data, $set) = @arg{qw(element data set)};

    # De-serialize data
    $self->thaw_data(element => $element, data => $data->[0]);

    # Expect an arrayref of IDs.  Map these to new IDs.  Set as arrayref in data()
    my @element_data = ();
    foreach my $list_item_id (@{$element->data}) {
        my $real_list_item_id = $set->map_id( class => pkg('ListItem'),
                                              id    => $list_item_id );
        debug ("Mapping list_item_id '$list_item_id' => '$real_list_item_id'");
        push(@element_data, $real_list_item_id);
    }

    $element->data(\@element_data);
}





=head1 NAME

Krang::ElementClass::ListGroup - list group element class

=head1 SYNOPSIS

  $class = pkg('ElementClass::ListGroup')->new( name => "cars",
                                                size => 5,
                                                list_group => 'Make/Model/Year',
                    );


=head1 DESCRIPTION

Provides a pre-populated set of parametric HTML selectboxes 
based of the contents of a specified Krang::ListGroup.

Elements using this class must contain references to arrays in data(),
even if multiple is 0.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item list_group

The name of an existing L<Krang::ListGroup>. Contents of list boxes
produced will be drawn from here.

=item size

The size of the select boxes on the edit screen.  Defaults to 5.
Setting this to 1 will create popup menus.

=item multiple

Set to true to allow multiple items to be selected at once.  This
will only work if there is only one list in the L<Krang::ListGroup> 
selected. Defaults to 0. You must set C<size> greater than 1
if you set C<multiple> to true.

=back

=head1 SEE ALSO

L<Krang::ListGroup>, L<Krang::List>, L<Krang::ListItem>,
HREF[The Krang Element System|element_system.html]

=cut

1;
