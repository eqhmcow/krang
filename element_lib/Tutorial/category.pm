package Tutorial::category;

use strict;
use warnings;

=head1 NAME

Tutorial::category

=head1 DESCRIPTION

category element class for Tutorial.  It has a display_name for a sub-element.

=cut

use base 'Krang::ElementClass::TopLevel';

sub new {

    my $pkg  = shift;

    my %args = ( name     => 'category',
                 children => [
                              Krang::ElementClass::Text->new(name => 'display_name',
                                                             allow_delete => 0,
                                                             min => 1,
                                                             max => 1,
                                                             reorderable => 0,
                                                             required => 1),
                             ],
                 @_);
    return $pkg->SUPER::new(%args);
}

1;
