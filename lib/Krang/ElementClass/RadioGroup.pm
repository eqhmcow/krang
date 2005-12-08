package Krang::ElementClass::RadioGroup;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass';
use Krang::ClassLoader 'ListGroup';
use Krang::ClassLoader 'List';
use Krang::ClassLoader 'ListItem';
use Carp qw(croak);

use Krang::ClassLoader MethodMaker => 
  get_set => [ qw( values labels columns list_group ) ];

sub new {
    my $pkg = shift;
    my %args = ( values     => [],
                 labels     => {},
                 columns    => 0,
                 list_group => '',
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $values = $self->values();
    my $labels = $self->labels();

    # if a list_group has been specified, use that instead
    if (my $group_name = $self->list_group) {
	($values, $labels) = $self->_get_list_data($group_name);
    }

    # Override built-in labels
    my %blank_labels = ( map { $_=>"" } @$values );

    # Make real labels
    my %attributes = ();
    my @click_labels = ();
    foreach my $v (@$values) {
        $attributes{$v} = {id=>$v};
        my $label = $labels->{$v};
        $label = $v unless (defined $label);
        push( @click_labels, 
              sprintf( '<label for="%s">%s</label>', 
                      scalar($query->escapeHTML($v)), 
                      scalar($query->escapeHTML($label)) ) 
            );
    }

    my @radio_buttons = $query->radio_group( -name       => $param,
                                             -default    => $element->data(),
                                             -values     => $values,
                                             -labels     => \%blank_labels,
                                             -attributes => \%attributes );

    # build html output
    my $html = "<table border=0 cellpadding=0 cellspacing=1>\n<tr>\n";
    my $count = 0;
    foreach my $rb (@radio_buttons) {
        $html .= "  <td><nobr>$rb".$click_labels[$count]."</nobr></td>\n";
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


sub _get_list_data {
    my ($self, $group_name) = @_;
    my ($lg) = pkg('ListGroup')->find(name=>$group_name);
    my @lists = pkg('List')->find(list_group_id=>$lg->list_group_id);

    # for now just use the first list found
    my @values;
    my %labels;
    if (scalar @lists > 0) {
	my @items = pkg('ListItem')->find(list_id=>$lists[0]->list_id);
	foreach my $item (@items) {
	    push(@values, $item->list_item_id);
	    $labels{$item->list_item_id} = $item->data;
	}
    }
    return (\@values, \%labels);
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


=item labels

A reference to a hash mapping C<values> to display names.


=item columns

The number of columns in which you want your radio group to appear.
This defaults to 0, which indicates that radio buttons be put horizontally.


=item list_group

If specified, this will populate the RadioGroup from a Krang list.


=back

=cut

1;
