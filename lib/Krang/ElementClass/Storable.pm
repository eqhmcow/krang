package Krang::ElementClass::Storable;
use strict;
use warnings;

use base 'Krang::ElementClass';
use Storable qw(nfreeze thaw);
use MIME::Base64 qw(encode_base64 decode_base64);
use Carp qw( croak );

sub thaw_data {
    my ($class, %arg) = @_;
    my ($element, $data) = @arg{qw(element data)};
    if (defined $data and length $data) {
        eval { $element->data(thaw(decode_base64($data))) };
        croak("Problem thawing data '$data': $@") if $@;
    }
}

sub freeze_data {
    my $element = $_[2];
    my $ret;
    if ($element->data) {
        eval { $ret = encode_base64(nfreeze($element->data)) };
        croak("Problem freezing data: $@") if $@;
    }
    return $ret;
}

sub check_data {
    my ($class, %arg) = @_;
    croak("Storable element classes require refs in data().")
      unless not defined $arg{data} or ref($arg{data});
}

=head1 NAME

Krang::ElementClass::Storable - parent class for elements with complex data

=head1 SYNOPSIS

  use base 'Krang::ElementClass::Storable';

=head1 DESCRIPTION

This module overrides the freeze_data and thaw_data methods in
Krang::ElementClass to use Storable to handle complex data.  If you
use this base class then you can store references and objects in C<<
$element->data() >> with impunity.

=head1 INTERFACE

None.

=cut

1;
