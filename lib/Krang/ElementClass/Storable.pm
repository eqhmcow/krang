package Krang::ElementClass::Storable;
use strict;
use warnings;

use base 'Krang::ElementClass';
use Storable qw(freeze thaw);

sub thaw_data {
    my ($class, %arg) = @_;
    my ($element, $data) = @arg{qw(element data)};
    if (defined $data and length $data) {
        eval { $element->data(thaw($data)) };
        croak("Problem thawing data '$data': $@") if $@;
    }
}

sub freeze_data {
    my $element = $_[2];
    my $ret;
    if ($element->data) {
        eval { $ret = freeze($element->data) };
        croak("Problem freezing data: $@") if $@;
    }
    return $ret;
}

=head1 NAME

Krang::ElementClass::Storable - parent class for elements with complex data

=head1 SYNOPSIS

  use base 'Krang::ElementClass::Storable';

=head1 DESCRIPTION

This module overrides the freeze_data and thaw_data methods in
Krang::ElementClass to use Storable to handle complex data.  If you
use this base class then you can story references and objects in C<<
$element->data() >> with impunity.

=head1 INTERFACE

None.

=cut

1;
