package Krang::ElementClass::MediaLink;
use strict;
use warnings;

use base 'Krang::ElementClass';

use Krang::MethodMaker
  get_set => [ qw( allow_upload show_thumbnail ) ];

sub new {
    my $pkg = shift;
    my %args = ( allow_upload   => 1,
                 show_thumbnail => 1,
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    return scalar $query->button(-name    => "find_media_$param",
                                 -value   => "Find Media",
                                 -onClick => "find_media('$param')",
                                ) 
      . ' or upload a new file: '
        . scalar $query->filefield(-name => $param);
}


=head1 NAME

Krang::ElementClass::Textarea - textarea element class

=head1 SYNOPSIS

   $class = Krang::ElementClass::MediaLink->new(name           => "photo",
                                                allow_upload   => 1,
                                                show_thumbnail => 1);

=head1 DESCRIPTION

Provides an element to link to media.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item allow_upload

Show an upload box in the editing interface to create new Media
objects inline.

=item show_thumbnail

Show a thumbnail of the media object in the editing interface.

=back

=cut

1;
