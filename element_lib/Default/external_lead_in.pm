package Default::external_lead_in;
use strict;
use warnings;

=head1 NAME

Default::external_lead_in

=head1 DESCRIPTION

Default external_lead_in element class for Krang.

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'external_lead_in',
                children => 
                [ 
                 Krang::ElementClass::ListBox->new(name => "type",
                                                   min => 1,
                                                   max => 1,
                                                   size => '2',
                                                   values => [ "Large",
                                                               "Small"],
                                                   default => ["Small"
                                                              ]),
                 Krang::ElementClass::Textarea->new(name => "title",
                                                    min => 1,
                                                    max => 1
                                                   ),
                 Krang::ElementClass::Textarea->new(name => "teaser",
                                                    min => 1,
                                                    max => 1
                                                   ),
                 Krang::ElementClass::Textarea->new(name => "URL",
                                                    min => 1,
                                                    max => 1,
                                                    required => 1
                                                   ),
                 Default::image->new(name => "image",
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
