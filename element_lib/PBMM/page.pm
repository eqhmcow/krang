package PBMM::page;
use strict;
use warnings;

=head1 NAME

PBMM::page

=head1 DESCRIPTION

PBMM article page class.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'page',
                min  => 1,
                pageable => 1,
                children => 
                [ 
                 Krang::ElementClass::Text->new(name => "large_header"),
                 Krang::ElementClass::Textarea->new(name => "paragraph",
                                                    bulk_edit => 1),
                 Default::image->new(),
                 Krang::ElementClass::MediaLink->new(name => "document_link",
                                                     display_name => "Document Link (PDF, Word, etc.)"),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

1;
