package Krang::ElementClass::Date;
use strict;
use warnings;

use base 'Krang::ElementClass';

use Krang::MethodMaker
  get_set => [ qw( size maxlength ) ];

sub new {
    my $pkg = shift;
    my %args = ( size      => 30,
                 maxlength => 0,
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $param = $element->xpath;
    return scalar $query->textfield(-name      => $param,
                                    -default   => $element->data() || "",
                                    -size      => $self->size,
                                    ($self->maxlength ? 
                                     (-maxlength => $self->maxlength) : ()));
}


=head1 NAME

Krang::ElementClass::Date - date element class

=head1 SYNOPSIS

  $class = Krang::ElementClass::Date->new(name         => "issue_date",
                                          default      => Time::Piece->new())

=head1 DESCRIPTION

Provides a date field element class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.  The
data() field for elements of this class stores a Time::Piece object.

=cut

1;
