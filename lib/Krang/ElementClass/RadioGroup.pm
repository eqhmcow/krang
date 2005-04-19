package Krang::ElementClass::RadioGroup;
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

    return scalar $query->radio_group(-name      => $param,
                                      -default   => $element->data(),
                                      -values    => $self->values(),
                                      -labels    => $self->labels());
}

=head1 NAME

Krang::ElementClass::RadioGroup - radio group element class

=head1 SYNOPSIS

  $class = pkg('ElementClass::RadioGroup')->new(name         => "alignment",
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
