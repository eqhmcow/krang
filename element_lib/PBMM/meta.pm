package PBMM::meta;
use strict;
use warnings;
use Default::keyword;


=head1 NAME

PBMM::meta - provides meta element classes for use by all story types

=head1 SYNOPSIS

  my @meta_classes = PBMM::meta->new();

=head1 DESCRIPTION

This class provides the basic "meta" elemenets for PBMM top-level
story types.

  Meta Keywords
  Meta Description
  Meta Company Type
  Meta Technology
  Meta Topic
  Meta Geography
  Meta Source

=cut

sub new {
    my @opt = (min          => 1, 
               max          => 1, 
               reorderable  => 0, 
               allow_delete => 0,
              );

    my @meta = 
      (
       Default::fancy_keyword->new(name => 'meta_keywords',
                                   display_name => 'Meta Keywords',
                                   @opt),
       Krang::ElementClass::Textarea->new( name => "meta_description",
                                           rows => 2,
                                           @opt),
       Krang::ElementClass::ListGroup->new( name     => "meta_company_type",
                                            list_group => 'Company Types',
                                          multiple => 1,
                                          size     => 5,
                                          @opt),
       Krang::ElementClass::ListGroup->new( name     => "meta_technology",
                                            list_group => 'Technologies',
                                          multiple => 1,
                                          size     => 5,
                                          @opt),
       Krang::ElementClass::ListGroup->new( name     => "meta_topic",
                                            list_group => 'Topics',
                                          multiple => 1,
                                          size     => 5,
                                          @opt),
       Krang::ElementClass::ListGroup->new( name     => "meta_geography",
                                            list_group => 'Geographies',
                                          multiple => 1,
                                          size     => 5,
                                          @opt),
       Krang::ElementClass::ListGroup->new( name     => "meta_source",
                                            list_group => 'Sources',
                                          multiple => 1,
                                          size     => 5,
                                          @opt),
      );

    return @meta;
}

1;
