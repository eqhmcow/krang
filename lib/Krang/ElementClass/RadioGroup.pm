package Krang::ElementClass::RadioGroup;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass';

use Krang::ClassLoader Log => qw(debug info);
use Krang::ClassLoader 'ListGroup';
use Krang::ClassLoader 'List';
use Krang::ClassLoader 'ListItem';
use Krang::ClassLoader Localization => qw(localize);
use Carp qw(croak);

use Krang::ClassLoader MethodMaker => get_set => [qw( values columns list_group )];

sub new {
    my $pkg  = shift;
    my %args = (
        values     => [],
        labels     => {},
        columns    => 0,
        list_group => '',
        @_
    );

    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $values = $self->values || [];
    my $labels = $self->labels || {};

    # if it's code, then call it to get the values
    $values = $values->($self, %arg) if ref $values eq 'CODE';
    $labels = $labels->($self, %arg) if ref $labels eq 'CODE';

    # if a list_group has been specified, use that instead
    if (my $group_name = $self->list_group) {
        ($values, $labels) = $self->_get_list_data($group_name);
    }

    # Override built-in labels
    my %blank_labels = (map { $_ => "" } @$values);

    # Make real labels
    my %attributes   = ();
    my @click_labels = ();
    foreach my $v (@$values) {
        $attributes{$v} = {id => $v};
        my $label = $labels->{$v};
        $label = $v unless (defined $label);
        push(
            @click_labels,
            sprintf(
                '<label for="%s">%s</label>',
                scalar($query->escapeHTML($v)),
                scalar($query->escapeHTML($label))
            )
        );
    }

    my @radio_buttons = $query->radio_group(
        -name       => $param,
        -default    => $element->data(),
        -values     => $values,
        -labels     => \%blank_labels,
        -attributes => \%attributes
    );

    # build html output
    my $html  = "<table border=0 cellpadding=0 cellspacing=1>\n<tr>\n";
    my $count = 0;
    foreach my $rb (@radio_buttons) {
        $html .= "  <td><nobr>$rb" . $click_labels[$count] . "</nobr></td>\n";
        $count++;
        if (my $cols = $self->columns) {
            unless ($count % $cols) {

                # New row needed
                $html .= "</tr>\n<tr>\n";
            }
        }
    }
    $html .= "</tr>\n</table\n>";

    return $html;
}

sub view_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};

    my $data = $element->data;
    return '' unless $data;

    my $labels = $self->labels;

    return %$labels ? $labels->{$data} : $data;
}

# do the normal XML serialization, but also include the linked list_item
# object in the dataset
sub freeze_data_xml {
    my ($self, %arg) = @_;
    my ($element, $writer, $set) = @arg{qw(element writer set)};

    # add list item object, IF we're in list_group mode
    if (my $lg_name = $self->list_group) {
        my $list_item_id = $element->data;
        my ($li) = pkg('ListItem')->find(list_item_id => $list_item_id);
        unless ($li) {
            info(   "Can't find list item for list_item_id '"
                  . ($list_item_id || "")
                  . "'.  Dropping it from KDS.");

            # Clear out data if we don't have an element
            $element->data(undef);
        } else {

            # Debugging
            my $element_id = $element->element_id();
            debug(
                "Adding list_item_id '$list_item_id' associated with element_id '$element_id' to KDS"
            );

            # Add to set
            $set->add(object => $li, from => $element->object);
        }
    }

    # Write XML for this element
    $self->SUPER::freeze_data_xml(%arg);
}

# translate the incoming list_item_id into a real ID
sub thaw_data_xml {
    my ($self, %arg) = @_;
    my ($element, $data, $set) = @arg{qw(element data set)};

    $self->thaw_data(element => $element, data => $data->[0]);

    # Return now unless we're in list_group mode
    return unless ($self->list_group);

    # If this is a listgroup-based element...
    # Expect an arrayref of IDs.  Map these to new IDs.  Set as arrayref in data()
    my $list_item_id = $element->data();

    # Bail if we have no data
    return unless defined $list_item_id;

    my $real_list_item_id = $set->map_id(
        class => pkg('ListItem'),
        id    => $list_item_id
    );
    debug("Mapping list_item_id $list_item_id => $real_list_item_id");
    $element->data($real_list_item_id);
}

sub _get_list_data {
    my ($self, $group_name) = @_;
    my ($lg) = pkg('ListGroup')->find(name => $group_name);
    my @lists = pkg('List')->find(list_group_id => $lg->list_group_id);

    # for now just use the first list found
    my @values;
    my %labels;
    if (scalar @lists > 0) {
        my @items = pkg('ListItem')->find(list_id => $lists[0]->list_id);
        foreach my $item (@items) {
            push(@values, $item->list_item_id);
            $labels{$item->list_item_id} = $item->data;
        }
    }
    return (\@values, \%labels);
}

sub labels {
    my ($self, $val) = @_;

    $self->{labels} = $val if $val;

    return $self->{labels} if ref($self->{labels}) eq 'CODE';

    my %localized_labels = ();

    if (%{$self->{labels}}) {

        # We've got labels
        while (my ($key, $val) = each %{$self->{labels}}) {
            $localized_labels{$key} = localize($key);
        }
    } else {

        # We've only got values
        for my $val (@{$self->{values}}) {
            $localized_labels{$val} = localize($val);
        }
    }

    return \%localized_labels;
}

=head1 NAME

Krang::ElementClass::RadioGroup - radio group element class

=head1 SYNOPSIS

  # Create radio group from static elements
  $class = pkg('ElementClass::RadioGroup')->new(
                     name         => "alignment",
                     values       => [ 'center', 'left', 'right' ],
                     labels       => { center => "Center",
                                       left   => "Left",
                                       right  => "Right" },
                     columns      => 2 );


  # Create radio group from Krang list group
  $class = pkg('ElementClass::RadioGroup')->new(
                     name         => "thingies",
                     list_group   => "article_thingies",
                     columns      => 2 );


=head1 DESCRIPTION

Provides a radio group element class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4


=item values

A reference to an array of values for the select box.

This can also be a code reference that will return an array reference.
This is really helpful when you don't know ahead of time what possible
values might be in the list, or they might change based on other actions.
This code reference will be called as a method in the element class with the
same arguments that are passed to element class's C<input_form()>.

=item labels

A reference to a hash mapping C<values> to display names.

This can also be a code reference that will return a hash reference.
This is really helpful when you don't know ahead of time what possible
values might be in the list, or they might change based on other actions.
This code reference will be called as a method in the element class with the
same arguments that are passed to element class's C<input_form()>.

=item columns

The number of columns in which you want your radio group to appear.
This defaults to 0, which indicates that radio buttons be put horizontally.

=item list_group

If specified, this will populate the RadioGroup from a Krang list.

=back

=cut

1;
