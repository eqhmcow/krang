package Krang::ElementClass::CheckBoxGroup;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass';
use Krang::ClassLoader Log => qw(debug info);
use Krang::ClassLoader 'ListGroup';
use Krang::ClassLoader 'List';
use Krang::ClassLoader 'ListItem';
use Carp qw(croak);

use Krang::ClassLoader MethodMaker => 
  get_set => [ qw( values labels defaults list_group columns ) ];

sub new {
    my $pkg = shift;
    my %args = ( values     => [],
                 labels     => {},
		 list_group => '',
		 columns    => 1,
		 defaults   => [],
                 @_
               );
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param)  = $self->param_names(element=>$element);
    my $defaults = $element->data || $self->defaults || [];

    my $values = $self->values;
    my $labels = $self->labels;

    # given a list_group name, find:
    # 1) the list group object;
    # 2) the lists for this group;
    # 3) use the first list in the group;
    # 4) and get the items for that list;
    if (my $group_name = $self->list_group) {
	($values, $labels) = $self->_get_list_data($group_name);
    }

    # Set up clickable (in IE) checkbox labels
    my @click_labels = ();
    my %attributes = ();
    foreach my $v (@$values) {
        $attributes{$v} = {id=>$v};
        my $l = $labels->{$v};

        # ucfirst each word if we don't have a label
        $l = join " ", 
          map { ucfirst($_) } 
            split /_/, $v
              unless defined $l;

        my $label = sprintf( '<label for="%s">%s</label>', 
                             $query->escapeHTML($v), 
                             $query->escapeHTML($l) );

        push(@click_labels, $label);
    }

    my @check_boxes = $query->checkbox_group( -name       => $param,
                                              -values     => $values,
                                              -attributes => \%attributes,
                                              -nolabels   => 1,
                                              -default    => $defaults );

    # Build checkbox UI
    my $html = "";

    # How many columns?
    my $columns = $self->columns();

    $html .= "<table border=0 cellpadding=0 cellspacing=0>\n<tr>\n";

    my $rows = int(0.99 + scalar(@check_boxes) / $columns);
    foreach my $row (0..$rows-1) {
        foreach my $column (0..$columns-1) {
            my $offset = $row + ($rows * $column);
            $html .= "    <td valign='top'><nobr>". $check_boxes[$offset] . $click_labels[$offset] ."</nobr></td>\n"
              unless (($offset) >= scalar(@check_boxes));
        }
        $html .= "</tr>\n<tr>\n";
    }

    $html .= "</tr>\n</table>\n";
    return $html;
}

sub _get_list_data {
    my ($self, $group_name) = @_;
    my ($lg) = pkg('ListGroup')->find(name=>$group_name);
    my @lists = pkg('List')->find(list_group_id=>$lg->list_group_id);

    # for now just use the first list found
    my @values;
    my %labels;
    if (scalar @lists > 0) {
	# BTW: ListItem docs are incorrect in the example shown;
	# It says you can use "list" when it should be "list_id";
	my @items = pkg('ListItem')->find(list_id=>$lists[0]->list_id);
	foreach my $item (@items) {
	    push(@values, $item->list_item_id);
	    $labels{$item->list_item_id} = $item->data;
	}
    }
    return (\@values, \%labels);
}

sub view_data {
    my ($self, %arg) = @_;
    my $sep  = ", ";
    my $labels = $self->labels;
    if (my $group_name = $self->list_group) {
	(undef, $labels) = $self->_get_list_data($group_name);
    }
    my $data = $arg{element}->data || [];
    return join($sep, map{ $labels->{$_} } @$data);
}

sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element=>$element);

    # Always use arrayref to avoid issues with
    # "@vals=$query->param('foo')" vs "$val=$query->param('foo')".
    $element->data([$query->param($param)]);
}

## The default freeze_data will store the literal string "ARRAY(0x1d41578)"
## instead of the multiple values. Store as pipe-separated list instead.
## I chose "|" because it is less likely to be used as a real value.
sub freeze_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    my $data    = $element->data || [];
    return join("|", @$data);
}

sub thaw_data {
    my ($self, %arg) = @_;
    my ($element, $text) = @arg{qw(element data)};
    $text ||= "";

    # Convert "XXX|YYY|ZZZ" to [XXX, YYY, ZZZ]
    return $element->data([ split(/\|/, $text) ]);
}


# do the normal XML serialization, but also include the linked list_item
# object in the dataset
sub freeze_data_xml {
    my ($self, %arg) = @_;
    my ($element, $writer, $set) = @arg{qw(element writer set)};

    # add list item object, IF we're in list_group mode
    if (my $lg_name = $self->list_group) {
        my $rlist_item_ids = $element->data;
        my @real_element_data = ();  # Delete items which don't have ListItems anymore
        foreach my $list_item_id (@$rlist_item_ids) {
            my ($li) = pkg('ListItem')->find(list_item_id=>$list_item_id);
            unless ($li) {
                info ("Can't find list item for list_item_id '$list_item_id'.  Dropping it from KDS.");
                next;
            }
            my $element_id = $element->element_id();
            debug ("Adding list_item_id '$list_item_id' associated with element_id '$element_id' to KDS");
            $set->add(object => $li, from => $element->object);
           push(@real_element_data, $list_item_id);  # Only valid list_item_ids
        }
       $element->data(\@real_element_data);
    }

    # Write XML for this element
    $self->SUPER::freeze_data_xml(%arg);
}


# translate the incoming list_item_id into a real ID
sub thaw_data_xml {
    my ($self, %arg) = @_;
    my ($element, $data, $set) = @arg{qw(element data set)};

    # Convert "XXX|YYY|ZZZ" to [XXX, YYY, ZZZ]
    $self->thaw_data(element => $element, data => $data->[0]);

    # Return now unless we're in list_group mode
    return unless ($self->list_group);

    # If this is a listgroup-based element...
    # Expect an arrayref of IDs.  Map these to new IDs.  Set as arrayref in data()
    my @element_data = ();
    foreach my $list_item_id (@{$element->data}) {
        my $real_list_item_id = $set->map_id( class => pkg('ListItem'),
                                              id    => $list_item_id );
        debug ("Mapping list_item_id $list_item_id => $real_list_item_id");
        push(@element_data, $real_list_item_id);
    }

    $element->data(\@element_data);
}


sub template_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};

    # No data?
    return "" unless $element->data;

    # Ripped from ListGroup
    my @chosen;
    foreach my $e (@{$element->data}) {
        my $i = (pkg('ListItem')->find( list_item_id => $e ))[0] || '';
        push(@chosen, $i->data) if $i;
    }
    return join(', ', @chosen);
}




=head1 NAME

Krang::ElementClass::CheckBoxGroup - checkbox group element class

=head1 SYNOPSIS

  $class = pkg('ElementClass::CheckBoxGroup')->new(
                     name         => "alignment",
		     columns      => 3,
                     values       => [ 'center', 'left', 'right' ],
                     labels       => { center => "Centered",
                                       left   => "Left Aligned",
                                       right  => "Right Aligned" },
                     # use either values/labels OR list_group
                     list_group   => 'group_name',
                     defaults     => ['center'],
		    );
                                                             

=head1 DESCRIPTION

Provides a checkbox element class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item values

A reference to an array of values for the checkboxes.

=item labels

A reference to a hash mapping C<values> to display names.

=item list_group

Use the specified list group for the values and labels. If specified,
this will override any values specified in the values and labels
attributes. The current implementation uses the ListItems from the
first List in the ListGroup. No support for multi-dimensional
checkboxes.

=item columns

You may specify how many columns should be used to display your 
checkboxes.  For example, a two column display:

  [] Opt A    [] Opt E
  [] Opt B    [] Opt F
  [] Opt C    [] Opt G
  [] Opt D

Default is columns == 1.


=item defaults

Array reference of default checkboxes which should be checked at the
time of creation.

=back

=cut

1;
