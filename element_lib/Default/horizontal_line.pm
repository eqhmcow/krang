package Default::horizontal_line;
use strict;
use warnings;

=head1 NAME

Default::horizontal_line

=head1 DESCRIPTION

Default horizontal_line element class for Krang.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'horizontal_line',
                @_);
   return $pkg->SUPER::new(%args);
}

sub input_form {
    return '';
}

1;
