package PBMM::money;
use strict;
use warnings;
use base 'Krang::ElementClass::Text';

=head1 NAME

PBMM::money - text element which validates the monetary format '12.34'

=cut

# validation for monetary values
sub validate {
    my $self = shift;
    my %arg = @_;
    my $element = $arg{element};
    my $query   = $arg{query};
    my $value = $query->param($element->param_names);
    return (0, $element->display_name ." must be a dollar amount with no '\$' (ex. 10.50 or 10).")
      unless not length $value or $value =~ /^\d+(\.\d{2})?$/;
    return (1);
}

1;

