package Krang::ElementClass::ListBox;
use strict;
use warnings;

use base 'Krang::ElementClass';
use Storable qw(freeze thaw);
use Carp qw(croak);

use Krang::MethodMaker
  get_set => [ qw( size multiple values labels ) ];

sub new {
    my $pkg = shift;
    my %args = ( size      => 5,
                 multiple  => 0,
                 values    => [],
                 labels    => {},
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element, $order) = @arg{qw(query element order)};
    my $param = $self->{name} . "_" . $order;

    return scalar $query->scrolling_list(-name      => $param,
                                         -default   => $element->data(),
                                         -values    => $self->values(),
                                         -labels    => $self->labels(),
                                         -size      => $self->size(),
                                         ($self->multiple ? 
                                          (-multiple => 'true') : ()));
}

sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element, $order) = @arg{qw(query element order)};
    my $param = $self->{name} . "_" . $order;
    $element->data([$query->param($param)]);
}

sub thaw_data {
    my $class = shift;
    my %arg = @_;
    my ($element, $data) = @arg{qw(element data)};
    eval { $element->data($data ? thaw($data) : []) };
    croak("Problem thawing data '$data': $@") if $@;
}

sub freeze_data {
    my $element = $_[2];
    my $ret;
    eval { $ret = freeze($element->data || []) };
    croak("Problem freezing data: $@") if $@;
    return $ret;
}


=head1 NAME

Krang::ElementClass::ListBox - list box element class

=head1 SYNOPSIS

  $class = Krang::ElementClass::ListBox->new(name         => "color",
                                             size         => 1,
                     values       => [ 'red', 'white', 'blue' ],
                     labels       => { red   => "Red",
                                       white => "White",
                                       blue  => "Blue" });
                                                             

=head1 DESCRIPTION

Provides a list menu element class.  Otherwise known as a select box
in HTML, but differentiated from Krang::ElementClass::ListBox by the
fact that it never allows more than one option to be selected.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item size

The size of the select box on the edit screen.  Defaults to 5.
Setting this to 1 will create a popup menu, but it's better to use
Krang::ElementClass::PopupMenu for that.

=item multiple

Set to true to allow multiple items to be selected at once.  Default
to 0.  You must set C<size> greater than 1 if you set C<multiple>
true.

=item values

A reference to an array of values for the select box.

=item labels

A reference to a hash mapping C<values> to display names.

=back

=cut

1;
