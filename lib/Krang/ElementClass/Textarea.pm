package Krang::ElementClass::Textarea;
use strict;
use warnings;

use base 'Krang::ElementClass';

use Krang::MethodMaker
  get_set => [ qw( rows cols ) ];

sub new {
    my $pkg = shift;
    my %args = ( rows => 4,
                 cols => 40,
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    return scalar $query->textarea(-name     => $param,
                                   -default  => $element->data() || "",
                                   -rows     => $self->rows,
                                   -cols     => $self->cols);
}


=head1 NAME

Krang::ElementClass::Textarea - textarea element class

=head1 SYNOPSIS

   $class = Krang::ElementClass::Textarea->new(name => "paragraph",
                                               rows => 4,
                                               cols => 40);


=head1 DESCRIPTION

Provides a textarea element class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item rows

The number of rows in the textarea box.  Defaults to 4.

=item cols

The number of columns in the textarea box.  Defaults to 40.

=back

=cut

1;
