package PBMM::document;
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
   my %args = ( name => 'document',
                display_name => "Document Link (PDF, Word, etc.)",
                children => 
                [ 
                 Krang::ElementClass::CheckBox->new(name => 'protected',
                                                    min => 1,
                                                    max => 1
                                                   ),
                 Krang::ElementClass::Textarea->new(name => "caption",
                                                    min => 0,
                                                    max => 1
                                                   ),
                 Krang::ElementClass::Textarea->new(name => "copyright",
                                                    min => 0,
                                                    max => 1
                                                   ),
                 Krang::ElementClass::MediaLink->new(name => "file",
                                                     min => 1,
                                                     max => 1,
                                                     required => 1,
                                                     allow_delete => 0),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element, $order) = @arg{qw(query element order)};
    my ($header, $data);
    if ($header = $element->child('file') and
        $data   = $header->view_data) {
        return $data;
    }
    return '';
}

1;
