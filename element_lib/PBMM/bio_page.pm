package PBMM::bio_page;
use strict;
use warnings;

=head1 NAME

PBMM::page

=head1 DESCRIPTION

PBMM bio page class.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'bio_page',
                min  => 1,
                pageable => 1,
                children => 
                [ 
                 Krang::ElementClass::Text->new(name => "large_header"),
                 Krang::ElementClass::Text->new(name => "small_header"),
                 Krang::ElementClass::Textarea->new(name => "paragraph",
                                                    bulk_edit => 1),
                 PBMM::image->new(),
                 'document',
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

1;
