package PBMM::article_related_link_box;
use strict;
use warnings;

=head1 NAME

PBMM::article_related_link_box

=head1 DESCRIPTION

PBMM article_related_link_box element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'article_related_link_box',
                children => 
                [ 
                 PBMM::lead_in->new( name => 'link_box_lead_in',
                                        display_name => 'Lead In' ),
                 PBMM::external_lead_in->new(),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}


1;
