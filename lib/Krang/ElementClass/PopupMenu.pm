package Krang::ElementClass::PopupMenu;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass';
use Krang::ClassLoader Localization => qw(localize);
use Carp qw(croak);

use Krang::ClassLoader MethodMaker => 
  get_set => [ qw( values ) ];

sub new {
    my $pkg = shift;
    my %args = ( values    => [],
                 labels    => {},
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $values = $self->values || [];
    my $labels = $self->labels || {};
    # if it's code, then call it to get the values
    $values = $values->($self, %arg) if ref $values eq 'CODE';
    $labels = $labels->($self, %arg) if ref $labels eq 'CODE';

    return scalar $query->popup_menu(-name      => $param,
                                     -default   => $element->data(),
                                     -values    => $values,
                                     -labels    => $labels);
}

sub labels {
    my ($self, $val) = @_;

    $self->{labels} = $val if $val;

    return $self->{labels} if ref($self->{labels}) eq 'CODE';

    my %localized_labels = ();

    if (%{$self->{labels}}) {
	# We've got labels
	while ( my ($key, $val) = each %{$self->{labels}} ) {
	    $localized_labels{$key} = localize($val);
	}
    } else {
	# We've only got values
	for my $val (@{$self->{values}}) {
	    $localized_labels{$val} = localize($val);
	}
    }

    return \%localized_labels;
}

=head1 NAME

Krang::ElementClass::PopupMenu - popup menu element class

=head1 SYNOPSIS

  $class = pkg('ElementClass::PopupMenu')->new(name         => "alignment",
                     values       => [ 'center', 'left', 'right' ],
                     labels       => { center => "Center",
                                       left   => "Left",
                                       right  => "Right" });
                                                             

=head1 DESCRIPTION

Provides a popup menu element class.  Otherwise known as a select box
in HTML, but differentiated from Krang::ElementClass::ListBox by the
fact that it never allows more than one option to be selected.  As a
result, C<< $element->data() >> contains a scalar value for elements
of this class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item values

A reference to an array of values for the select box.

This can also be a code reference that will return an array reference.
This is really helpful when you don't know ahead of time what possible
values might be in the list, or they might change based on other actions.
This code reference will be called as a method in the element class with the
same arguments that are passed to element class's C<input_form()>.

=item labels

A reference to a hash mapping C<values> to display names.

This can also be a code reference that will return a hash reference.
This is really helpful when you don't know ahead of time what possible
values might be in the list, or they might change based on other actions.
This code reference will be called as a method in the element class with the
same arguments that are passed to element class's C<input_form()>.

=back

=cut

1;
