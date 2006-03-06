package TestParent1::keyword;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);

use Krang::ClassLoader base => 'ElementClass::Text';

sub new {
   my $pkg = shift;
   my %args = ( name => 'keyword',
                bulk_edit => 1);
   return $pkg->SUPER::new(%args);
}

1;
