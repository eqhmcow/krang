package PBMM::search_type;
use strict;
use warnings;

=head1 NAME

PBMM::search_type

=head1 DESCRIPTION

PBMM search_type element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'search_type',
                children => 
                [
                    Krang::ElementClass::PopupMenu->new(name => "type",
                                                     values => [ "keyword",
                                                                 "topic",
                                                                 "multisite",
                                                                 "custom"],
                                                     default => "keyword",
                                                    min => 1,
                                                    max => 1,
                                                    allow_delete => 1,
                                                    reorderable => 0),
                    Krang::ElementClass::CheckBox->new(name => 'table_background',
                                                       min => 1,
                                                        max => 1,
                                                        allow_delete => 1,
                                                        reorderable => 0,
                                                        default => 0
                                                     ),
                     Krang::ElementClass::Text->new(name         => "table_title",
                                                    min => 1,
                                                        max => 1,
                                                        allow_delete => 1,
                                                        reorderable => 0 ), 
                ],
                @_);
   return $pkg->SUPER::new(%args);
}


1;
