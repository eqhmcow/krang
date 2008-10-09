package Krang::ElementClass::Text;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass';

use Krang::ClassLoader MethodMaker => get_set => [qw( size maxlength )];

sub new {
    my $pkg  = shift;
    my %args = (
        size      => 30,
        maxlength => 0,
        @_
    );

    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    return scalar $query->textfield(
        -name    => $param,
        -default => $element->data() || "",
        -size    => $self->size,
        ($self->maxlength ? (-maxlength => $self->maxlength) : ())
    );
}

=head1 NAME

Krang::ElementClass::Text - text element class

=head1 SYNOPSIS

  $class = pkg('ElementClass::Text')->new(name         => "header",
                                          maxlength    => 0,
                                          size         => 30);

=head1 DESCRIPTION

Provides a text box element class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item size

The size of the text box on the edit screen.  Defaults to 30.

=item maxlength

The maximum number of characters the user will be allowed to enter.
Defaults to 0, meaning no limit.

=back

=cut

1;
