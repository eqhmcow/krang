package TestParent1::keyword;
use strict;
use warnings;

use base 'Krang::ElementClass::Text';

sub new {
   my $pkg = shift;
   my %args = ( name => 'keyword',
                bulk_edit => 1);
   return $pkg->SUPER::new(%args);
}

1;
