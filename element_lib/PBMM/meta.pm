package PBMM::meta;
use strict;
use warnings;
use Default::keyword;

#
# Source Lists
#

our @COMPANY_TYPES =
  ( "All",
    "Automakers",
    "Dealers/Distributors",
    "Other Organizations",
    "Suppliers" );

our @TECHNOLOGIES = 
  ( "All",
    "Chassis",
    "Mfg Tech & Processes",
    "Powertrain",
    "Vehicle Exterior",
    "Vehicle Interior" );

our @TOPICS = 
  ( "All", 
    "Financial",
    "Future Product Plans",
    "Heavy-Duty Trucking",
    "Management & Strategy",
    "Plant Use & Production",
    "Politics, Regulatory, Trade",
    "Product Devlpmt, Design, Engrg",
    "Sales/Marketing",
    "Supply Chain",
    "Vehicles" );

our @GEOGRAPHIES =
  ( "All",
    "Asia/Pacific",
    "Europe",
    "N. America",
    "Other Regions",
    "S. Americs",
    "World" );

our @SOURCES = 
  ( "Newswire",
    "Ward's AutoWorld Magazine",
    "Ward's Dealer Business Magazine",
    "WardsAuto.com" );

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
  Meta Technolgy
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
       Krang::ElementClass::ListBox->new( name     => "meta_company_type",
                                          multiple => 1,
                                          values   => \@COMPANY_TYPES,
                                          size     => 5,
                                          @opt),
       Krang::ElementClass::ListBox->new( name     => "meta_technology",
                                          multiple => 1,
                                          values   => \@TECHNOLOGIES,
                                          size     => 5,
                                          @opt),
       Krang::ElementClass::ListBox->new( name     => "meta_topic",
                                          multiple => 1,
                                          values   => \@TOPICS,
                                          size     => 5,
                                          @opt),
       Krang::ElementClass::ListBox->new( name     => "meta_geography",
                                          multiple => 1,
                                          values   => \@GEOGRAPHIES,
                                          size     => 5,
                                          @opt),
       Krang::ElementClass::ListBox->new( name     => "meta_source",
                                          multiple => 1,
                                          values   => \@SOURCES,
                                          size     => 5,
                                          @opt),
      );

    return @meta;
}

1;
