package TestSet1::category;
use strict;
use warnings;

=head1 NAME

TestSet1::category

=head1 DESCRIPTION

Example category element class for Krang.  It has no subelements at the
moment.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'category',
                @_);
   return $pkg->SUPER::new(%args);
}

1;

   
