package PBMM::custom_targeting;
use strict;
use warnings;

=head1 NAME

PBMM::document

=head1 DESCRIPTION

PBMM document element class for Krang. Has a caption and copyright
that will override assoicated media caption/copyright if set.
It also has a 'protected' checkbox.
=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'custom_targeting',
                children => 
                [ 
                 Krang::ElementClass::Textarea->new(name => "keyword_1",
                                                    min => 1,
                                                    max => 1,
                                                    allow_delete => 0,
                                                    reorderable => 0
                                                   ),
                Krang::ElementClass::Textarea->new(name => "keyword_2",                                                    min => 1,
                                                    max => 1,
                                                    reorderable => 0,
                                                    allow_delete => 0
                                                   ),
                Krang::ElementClass::Textarea->new(name => "keyword_3",                                                    min => 1,
                                                    max => 1,
                                                    reorderable => 0,
                                                    allow_delete => 0
                                                   ),
                Krang::ElementClass::Textarea->new(name => "keyword_4",                                                    min => 1,
                                                    max => 1,
                                                    reorderable => 0,
                                                    allow_delete => 0
                                                   ),
                Krang::ElementClass::Textarea->new(name => "keyword_5",                                                    min => 1,
                                                    max => 1,
                                                    reorderable => 0,
                                                    allow_delete => 0
                                                   ),

                ],
                @_);
   return $pkg->SUPER::new(%args);
}

1;
