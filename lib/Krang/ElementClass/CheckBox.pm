package Krang::ElementClass::CheckBox;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass';
use Carp qw(croak);

use Krang::ClassLoader MethodMaker => 
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
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    return scalar $query->checkbox(-name      => $param,
                                   -checked   => $element->data() ? 1 : 0,
                                   -value     => $self->value(),
                                   -label     => '');
}

=head1 NAME

Krang::ElementClass::CheckBox - check box element class

=head1 SYNOPSIS

  $class = pkg('ElementClass::CheckBox')->new(name => "show_sprinks",
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
