package TestSet1::publishtest;

use strict;
use warnings;

=head1 NAME

TestSet1::publish_test

=head1 DESCRIPTION

An example element class for Krang, used for testing the Krang publish
system.

This element contains single 'deck', and 'headline' fields, along with
one or more pages.

=cut

use base 'Krang::ElementClass::TopLevel';


sub new {

    my $pkg  = shift;
    my %args = ( name => 'publishtest',
                 children =>
                 [
                  Krang::ElementClass::Text->new(name => 'headline',
                                                     min => 1,
                                                     max => 1,
                                                     reorderable => 0,
                                                     allow_delete => 0,
                                                     indexed => 1,
                                                    ),
                  Krang::ElementClass::Textarea->new(name => 'deck',
                                                     min => 1,
                                                     max => 1,
                                                     reorderable => 0,
                                                     allow_delete => 0,
                                                     indexed => 1,
                                                    ),
                  'page',
                 ],
                 @_);
    return $pkg->SUPER::new(%args);
}


# override publish_category_per_page to force republishing of category
# templates on each page of a story.

sub publish_category_per_page { 1 }


1;
