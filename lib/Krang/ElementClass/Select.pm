package Krang::ElementClass::Select;
use strict;
use warnings;

use constant VERBOSE => 1;

use base 'Krang::ElementClass';
use Storable qw(freeze thaw);
BEGIN { require Data::Dumper if VERBOSE }
use Carp qw(croak);

use Krang::MethodMaker
  get_set => [ qw( size multiple values labels ) ];

sub new {
    my $pkg = shift;
    my %args = ( size      => 1,
                 multiple  => 0,
                 values    => [],
                 labels    => {},
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element, $order) = @arg{qw(query element order)};
    my $param = $self->{name} . "_" . $order;

    if ($self->size == 1) {
        return scalar $query->popup_menu(-name      => $param,
                                         -default   => $element->data()->[0],
                                         -values    => $self->values(),
                                         -labels    => $self->labels());
    } else {
        return scalar $query->scrolling_list(-name      => $param,
                                         -default   => $element->data(),
                                         -values    => $self->values(),
                                         -labels    => $self->labels(),
                                         -size      => $self->size(),
                                         ($self->multiple ? 
                                          (-multiple => 'true') : ()));
    }
}

sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element, $order) = @arg{qw(query element order)};
    my $param = $self->{name} . "_" . $order;
    $element->data([$query->param($param)]);
}

sub thaw_data {
    my $class = shift;
    my %arg = @_;
    my ($element, $data) = @arg{qw(element data)};
    if (VERBOSE) {
        no strict 'vars';
        $element->data($data ? eval $data : []);
    } else {
        eval { $element->data($data ? thaw($data) : []) };
    }
    croak("Problem thawing data '$data': $@") if $@;
}

sub freeze_data {
    my $element = $_[2];
    my $ret;
    if (VERBOSE) {
        eval { $ret = Data::Dumper->Dump([$element->data || []],['UNUSED']); };
    } else {
        eval { $ret = freeze($element->data || []) };
    }
    croak("Problem freezing data: $@") if $@;
    return $ret;
}


=head1 NAME

Krang::ElementClass::Select - text element class

=head1 SYNOPSIS

  $class = Krang::ElementClass::Select->new(name         => "alignment",
                                            size         => 1,
                     values       => [ 'center', 'left', 'right' ],
                     labels       => { center => "Center",
                                       left   => "Left",
                                       right  => "Right" });
                                                             

=head1 DESCRIPTION

Provides a select box element class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item size

The size of the select box on the edit screen.  Defaults to 1 which
produces a popup menu.  Values greater than 1 will create a list box.

=item values

A reference to an array of values for the select box.

=item labels

A reference to a hash mapping C<values> to display names.

=item multiple

Set to true to allow multiple items to be selected at once.  Default
to 0.  You must set C<size> greater than 1 if you set C<multiple>
true.

=back

=head1 TODO

multiple doesn't work.  needs overriden load_query_data and
serialize/deserialize.  Speaking of which, serialize/deserialize need
to work.

=cut

1;
