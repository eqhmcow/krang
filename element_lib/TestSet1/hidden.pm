package TestSet1::hidden;

use strict;
use warnings;

=head1 NAME

TestSet1::article

=head1 DESCRIPTION

Example hidden-story class for Krang.  This element contains one or
more paragraphs, and is flagged as hidden.  It will not show up in
calls to C<find()> unless certain criteria are met.  See
L<Krang::Story> and L<Krang::ElementClass::TopLevel> for more
information.

=cut


use base 'Krang::ElementClass::TopLevel';

sub hidden { 1 }

sub new {
   my $pkg = shift;
   my %args = ( name => 'hidden',
                children => 
                [
                 Krang::ElementClass::Textarea->new(name => 'paragraph')
                ],
                @_
              );

   return $pkg->SUPER::new(%args);
}


1;
