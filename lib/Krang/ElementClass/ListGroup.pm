package Krang::ElementClass::ListGroup;
use strict;
use warnings;

use base 'Krang::ElementClass::Storable';
use Carp qw(croak);

#use Krang::ListGroup;
#use Krang::List;
#use Krang::ListItem;

use Krang::MethodMaker
  get_set => [ qw( size multiple list_group ) ];

sub new {
    my $pkg = shift;
    my %args = ( size      => 5,
                 multiple  => 0,
                 list_group    => '',
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub check_data {
    my ($class, %arg) = @_;
    croak("ListGroup element class requires an array-ref in data().")
      unless not defined $arg{data} or 
        (ref($arg{data}) and ref($arg{data}) eq 'ARRAY');
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    require Krang::ListGroup;
    require Krang::List;
    require Krang::ListItem;

    my ($lg) = Krang::ListGroup->find( name => $self->list_group() );

    my @lists = Krang::List->find( list_group_id => $lg->list_group_id );

    my $output;

    if (@lists > 1) {
        foreach my $list (@lists) {
            my @items = Krang::ListItem->find( list_id => $list->list_id );
        }
    } else {

        my @items = Krang::ListItem->find( list_id => $lists[0]->list_id );

        my @values = map { $_->list_item_id } @items;
        my %labels = map { $_->list_item_id => $_->data } @items;

        my $default;
        if ($self->multiple) {
            $default = $element->data || [];
        } else {
            $default = $element->data ? $element->data()->[0] : "";
        }

        $output = scalar $query->scrolling_list(-name      => $param,
                                             -default   => $default,
                                             -values    => \@values,
                                             -labels    => \%labels,
                                             -size      => $self->size(),
                                             ($self->multiple ? 
                                              (-multiple => 'true') : ()));
    }
    return $output;
}

sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $param = $element->xpath;
    $element->data([$query->param($param)]);
}

sub template_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    return "" unless $element->data;
    require Krang::ListItem;
    my @chosen;
    foreach my $e (@{$element->data}) {
        my $i = (Krang::ListItem->find( list_item_id => $e ))[0] || '';
        push(@chosen, $i->data) if $i;
    }
    return join(', ', @chosen);
}

sub view_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    return "" unless $element->data;
    require Krang::ListItem;
    my @chosen; 
    foreach my $e (@{$element->data}) {
        my $i = (Krang::ListItem->find( list_item_id => $e ))[0] || '';
        push(@chosen, $i->data) if $i;
    }
    return join("<br>", @chosen);
}

=head1 NAME

Krang::ElementClass::ListGroup - list group element class

=head1 SYNOPSIS

  $class = Krang::ElementClass::ListGroup->new( name => "cars",
                                                size => 5,
                                                list_group => 'Make/Model/Year',
                    );
                                                             

=head1 DESCRIPTION

Provides a pre-populated set of parametric HTML selectboxes 
based of the contents of a specified Krang::ListGroup.

Elements using this class must contain references to arrays in data(),
even if multiple is 0.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item list_group

The name of an existing L<Krang::ListGroup>. Contents of list boxes
produced will be drawn from here.

=item size

The size of the select boxes on the edit screen.  Defaults to 5.
Setting this to 1 will create popup menus.

=item multiple

Set to true to allow multiple items to be selected at once.  This
will only work if there is only one list in the L<Krang::ListGroup> 
selected. Defaults to 0. You must set C<size> greater than 1
if you set C<multiple> to true.

=back

=head1 SEE ALSO

L<Krang::ListGroup>, L<Krang::List>, L<Krang::ListItem>,
HREF[The Krang Element System|element_system.html]

=cut

1;
