package Krang::ElementClass::RadioGroup;
use strict;
use warnings;

use base 'Krang::ElementClass';
use Carp qw(croak);

use Krang::MethodMaker
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
    my $param = $element->xpath;

    return scalar $query->radio_group(-name      => $param,
                                      -default   => $element->data(),
                                      -values    => $self->values(),
                                      -labels    => $self->labels());
}

=head1 NAME

Krang::ElementClass::RadioGroup - radio group element class

=head1 SYNOPSIS

  $class = Krang::ElementClass::RadioGroup->new(name         => "alignment",
                     values       => [ 'center', 'left', 'right' ],
                     labels       => { center => "Center",
                                       left   => "Left",
                                       right  => "Right" });
                                                             

=head1 DESCRIPTION

Provides a radio group element class.

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
