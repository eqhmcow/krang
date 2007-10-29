# NOTE - THIS IS NOW A DEPRECATED CLASS:
# SLUGS ARE OPTIONAL FOR ALL TOPLEVEL ELEMENTS.

package Krang::ElementClass::Cover;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass::TopLevel';

sub slug_use {
    return 'discourage';
}


=head1 NAME

Krang::ElementClass::Cover - cover element base class

=head1 SYNOPSIS

  package my::Cover;
  use base 'Krang::ElementClass::Cover';

=head1 DESCRIPTION

This is now a deprecated class: Previous to version 3 of Krang,
types that subclassed Cover always ignored their slug value;
now slugs are available and optional for all story types.

As a result, the only remaining behavior is a slug_use()
value of 'discourage': When a new Cover-based story is created in the CGI, 
it will by default have no slug, but the user can override this.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.

=cut

1;
