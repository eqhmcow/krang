package Krang::ElementClass::ListGroup;
use strict;
use warnings;

use base 'Krang::ElementClass::Storable';
use Carp qw(croak);

#use Krang::ListGroup;
#use Krang::List;
#use Krang::ListItem;

use Krang::MethodMaker
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

    require Krang::ListGroup;
    require Krang::List;
    require Krang::ListItem;

    my ($lg) = Krang::ListGroup->find( name => $self->list_group() );

    my ($all_pulldowns, $html_output);

    # iterate over the lists in this listgroup, building scrolling
    # lists for each one.
    my $list_index = 0;

    my @lists = Krang::List->find( list_group_id => $lg->list_group_id );

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
<script language="javascript">
  // Javascript to manage listgroup $jparam
  var ${jparam}_data = new Array();
  var ${jparam}_index = new Array();
END


        # grab the list of items for the first list in the listgroup:
        my $x = 0;
        my @root_items = Krang::ListItem->find( list_id => $root_list->list_id,
                                                no_parent => 1,
                                              );
        foreach my $item (@root_items) {
            _add_item(\$html_output, $item, "${jparam}_data[$x]", $jparam);
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
                      -default => $element->data ? $element->data()->[$list_index] : ""
                     );


        # only populate scrolling listbox for the first list - the
        # rest will be done w/ javascript.

        my %find_params = (list_id => $list->list_id);
        $find_params{parent_list_item_id} = $element->data()->[($list_index - 1)] 
          if ($list_index && $element->data());

        @items = Krang::ListItem->find( %find_params );

        @values = map { $_->list_item_id } @items;
        %labels = map { $_->list_item_id => $_->data } @items;

        if ($self->multiple) {
            $params{-default} = $element_data->[$list_index] || [];
            $params{-multiple} = 'true';
        }

        $params{-values}  = \@values;
        $params{-labels}  = \%labels;

        # make the jscript call if it is multidimensional
        if ($#lists > 0) {
            $params{-onclick} = "${jparam}_update(this, $list_index);";
        }

        my $pulldown = scalar $query->scrolling_list(%params);

        $pulldown =~ s!<select!<select id="${param}_${list_index}"!i;

        $all_pulldowns .= sprintf("<strong>%s</strong><BR>\n%s<BR>\n",
                              $list->name, $pulldown);

        $list_index++;
    }

    $html_output .= $all_pulldowns;

    return $html_output;
}

#
# _add_item is used to build out the javascript array for multidimensional lists.
#
sub _add_item {
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
    my @sub_items = Krang::ListItem->find(parent_list_item_id => $id);
    if (@sub_items) {
        my $x = -1;
        $$html .= $pre. qq{["sub"] = new Array();\n};
        foreach my $item (@sub_items) {
            $x++;
            _add_item($html, $item, $pre . qq{["sub"][$x]}, $jparam, ($stop || 0) + 1);
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
    require Krang::ListItem;
    my @chosen;
    foreach my $e (@{$element->data}) {
        my $i = (Krang::ListItem->find( list_item_id => $e ))[0] || '';
        push(@chosen, $i->data) if $i;
    }
    return join(', ', @chosen);
}

sub view_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    return "" unless $element->data;
    require Krang::ListItem;
    my @chosen; 
    foreach my $e (@{$element->data}) {
        my $i = (Krang::ListItem->find( list_item_id => $e ))[0] || '';
        push(@chosen, $i->data) if $i;
    }
    return join("<br>", @chosen);
}

=head1 NAME

Krang::ElementClass::ListGroup - list group element class

=head1 SYNOPSIS

  $class = Krang::ElementClass::ListGroup->new( name => "cars",
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
