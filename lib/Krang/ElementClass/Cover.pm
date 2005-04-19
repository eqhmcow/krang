package Krang::ElementClass::Cover;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass::TopLevel';

sub build_url {
    my ($self, %arg) = @_;
    return $arg{category} ? $arg{category}->url : "";
}

sub build_preview_url {
    my ($self, %arg) = @_;
    return $arg{category} ? $arg{category}->preview_url : "";
}

sub url_attributes { () }


=head1 NAME

Krang::ElementClass::Cover - cover element base class

=head1 SYNOPSIS

  package my::Cover;
  use base 'Krang::ElementClass::Cover';

=head1 DESCRIPTION

Provides a base class for cover element classes.  Overrides
C<build_url()> to provide a URL that just uses site URL and category
path data, without taking into account the story slug.  Also overrides
C<url_attributes()> to correctly report that no story attributes are
used in the URL.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.

=cut

1;
