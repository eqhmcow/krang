package PBMM::external_lead_in;
use strict;
use warnings;

=head1 NAME

PBMM::external_lead_in

=head1 DESCRIPTION

PBMM external_lead_in element class for Krang.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'external_lead_in',
                children => 
                [ 
                 Krang::ElementClass::Textarea->new(name => "promo_title",
                                                    min => 1,
                                                    max => 1,
                                                    allow_delete => 0
                                                   ),
                 Krang::ElementClass::Textarea->new(name => "promo_text",
                                                    min => 1,
                                                    max => 1,
                                                    allow_delete => 0
                                                   ),
                 Krang::ElementClass::Textarea->new(name => "promo_url",
                                                    display_name => 'URL',
                                                    min => 1,
                                                    max => 1,
                                                    required => 1,
                                                    allow_delete => 0
                                                   ),
                 Krang::ElementClass::MediaLink->new(name => "promo_image",
                                                     min => 1,
                                                     max => 1,
                                                     allow_delete => 0),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element, $order) = @arg{qw(query element order)};
    my ($header, $data);
    if ($header = $element->child('title') and
        $data   = $header->data) {
        return $data;
    }
    return '';
}

1;
