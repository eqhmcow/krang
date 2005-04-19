package Krang::ElementClass::PopupMenu;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass';
use Carp qw(croak);

use Krang::ClassLoader MethodMaker => 
  get_set => [ qw( values labels ) ];

sub new {
    my $pkg = shift;
    my %args = ( values    => [],
                 labels    => {},
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    return scalar $query->popup_menu(-name      => $param,
                                     -default   => $element->data(),
                                     -values    => $self->values(),
                                     -labels    => $self->labels());
}

=head1 NAME

Krang::ElementClass::PopupMenu - popup menu element class

=head1 SYNOPSIS

  $class = pkg('ElementClass::PopupMenu')->new(name         => "alignment",
                     values       => [ 'center', 'left', 'right' ],
                     labels       => { center => "Center",
                                       left   => "Left",
                                       right  => "Right" });
                                                             

=head1 DESCRIPTION

Provides a popup menu element class.  Otherwise known as a select box
in HTML, but differentiated from Krang::ElementClass::ListBox by the
fact that it never allows more than one option to be selected.  As a
result, C<< $element->data() >> contains a scalar value for elements
of this class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item values

A reference to an array of values for the select box.

=item labels

A reference to a hash mapping C<values> to display names.

=back

=cut

1;
