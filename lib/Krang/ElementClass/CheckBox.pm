package Krang::ElementClass::CheckBox;
use strict;
use warnings;

use base 'Krang::ElementClass';
use Carp qw(croak);

use Krang::MethodMaker
  get_set => [ qw( value ) ];

sub new {
    my $pkg = shift;
    my %args = ( value    => 1,
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element, $order) = @arg{qw(query element order)};
    my $param = $self->{name} . "_" . $order;

    return scalar $query->checkbox(-name      => $param,
                                   -checked   => $element->data() ? 1 : 0,
                                   -value     => $self->value(),
                                   -label     => '');
}

=head1 NAME

Krang::ElementClass::CheckBox - check box element class

=head1 SYNOPSIS

  $class = Krang::ElementClass::CheckBox->new(name => "show_sprinks",
                                              value => 1,
                                              default => 1);

=head1 DESCRIPTION

Provides a check box element class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item value

The value returned when the checkbox is checked.  Set this value as
the C<default> to indicate that the field starts checked.  Defaults to
1.

=back

=cut

1;
