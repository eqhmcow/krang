package PBMM::promo;
use strict;
use warnings;

=head1 NAME

PBMM::promo - provides promo element classes for use by all story types

=head1 SYNOPSIS

  my @promo_classes = PBMM::promo->new();

=head1 DESCRIPTION

This class provides the basic "promo" elements for PBMM top-level
story types.

    Promo Title
    Promo Teaser
    Promo Image Large
    Promo Image Small

=cut

sub new {
    my @meta = 
      (
        Krang::ElementClass::Text->new( display_name => 'Promo/SEO Title',
                                        name => 'promo_title',
                                        min  => 1,
                                        max  => 1,
                                        reorderable => 0,
                                        allow_delete => 0),
        Krang::ElementClass::Textarea->new( name => 'promo_teaser',
                                            min  => 1,
                                            max  => 1,
                                            reorderable => 0,
                                            allow_delete => 0),
        Krang::ElementClass::MediaLink->new(name => 'promo_image_small',
                                            max  => 1),
        Krang::ElementClass::MediaLink->new(name => 'promo_image_large',
                                            max  => 1),

      );

    return @meta;
}

1;
