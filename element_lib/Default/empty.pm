package Default::empty;
use strict;
use warnings;

=head1 NAME

Default::empty

=head1 DESCRIPTION

Default empty element class for Krang.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'empty',
                @_);
   return $pkg->SUPER::new(%args);
}

sub input_form {
    return '';
}

1;
