package Default::category;
use strict;
use warnings;

=head1 NAME

Default::category

=head1 DESCRIPTION

Default category element class for Krang.  It has no subelements at the
moment.

=cut


use base 'Krang::ElementClass::TopLevel';

sub new {
   my $pkg = shift;
   my %args = ( name => 'category',
                @_);
   return $pkg->SUPER::new(%args);
}

1;

   
