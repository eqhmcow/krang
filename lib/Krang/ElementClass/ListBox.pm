package Krang::ElementClass::ListBox;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass::Storable';
use Carp qw(croak);

use Krang::ClassLoader MethodMaker => 
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

sub check_data {
    my ($class, %arg) = @_;
    croak("ListBox element class requires an array-ref in data().")
      unless not defined $arg{data} or 
        (ref($arg{data}) and ref($arg{data}) eq 'ARRAY');
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $default;
    if ($self->multiple) {
        $default = $element->data || [];
    } else {
        $default = $element->data ? $element->data()->[0] : "";
    }

    my $values = $self->values || [];
    my $labels = $self->labels || {};
    # if it's code, then call it to get the values
    $values = $values->($self, %arg) if ref $values eq 'CODE';
    $labels = $labels->($self, %arg) if ref $labels eq 'CODE';

    return scalar $query->scrolling_list(-name      => $param,
                                         -default   => $default,
                                         -values    => $values,
                                         -labels    => $labels,
                                         -size      => $self->size(),
                                         ($self->multiple ? 
                                          (-multiple => 'true') : ()));
}

sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $param = $element->xpath;
    $element->data([$query->param($param)]);
}

sub template_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    return "" unless $element->data;
    return join(', ', @{$element->data});
}

sub view_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    return "" unless $element->data;
    return join("<br>", @{$element->data});
}

=head1 NAME

Krang::ElementClass::ListBox - list box element class

=head1 SYNOPSIS

  $class = pkg('ElementClass::ListBox')->new(name         => "color",
                                             size         => 1,
                     values       => [ 'red', 'white', 'blue' ],
                     labels       => { red   => "Red",
                                       white => "White",
                                       blue  => "Blue" }.
                     default      => [ 'white' ],
                    );
                                                             

=head1 DESCRIPTION

Provides a list menu element class.  Otherwise known as a select box
in HTML, but differentiated from Krang::ElementClass::ListBox by the
fact that it never allows more than one option to be selected.

Elements using this class must contain references to arrays in data(),
even if multiple is 0.

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

=back

=cut

1;
