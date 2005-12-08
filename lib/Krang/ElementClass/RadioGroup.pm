package Krang::ElementClass::RadioGroup;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass';
use Carp qw(croak);

use Krang::ClassLoader MethodMaker => 
  get_set => [ qw( values labels columns ) ];

sub new {
    my $pkg = shift;
    my %args = ( values    => [],
                 labels    => {},
                 columns   => 0,
                 @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $values = $self->values();
    my $labels = $self->labels();
    my %blank_labels = ( map { $_=>"" } @$values );

    # Make real labels
    my %attributes = ();
    my @click_labels = ();
    foreach my $v (@$values) {
        $attributes{$v} = {id=>$v};
        push( @click_labels, 
              sprintf( '<label for="%s">%s</label>', 
                      scalar($query->escapeHTML($v)), 
                      scalar($query->escapeHTML($labels->{$v})) ) 
            );
    }

    my @radio_buttons = $query->radio_group( -name       => $param,
                                             -default    => $element->data(),
                                             -values     => $values,
                                             -labels     => \%blank_labels,
                                             -attributes => \%attributes );

    # build html output
    my $html = "<table border=0 cellpadding=0 cellspacing=0>\n<tr>\n";
    my $count = 0;
    foreach my $rb (@radio_buttons) {
        $html .= "  <td><nobr>$rb ".$click_labels[$count]."</nobr></td>\n";
        $count++;
        if (my $cols = $self->columns) {
            unless ($count % $cols) {
                # New row needed
                $html .= "</tr>\n<tr>\n";
            }
        }
    }
    $html .= "</tr>\n</table\n>";

    return $html;
}

=head1 NAME

Krang::ElementClass::RadioGroup - radio group element class

=head1 SYNOPSIS

  $class = pkg('ElementClass::RadioGroup')->new(
                     name         => "alignment",
                     values       => [ 'center', 'left', 'right' ],
                     labels       => { center => "Center",
                                       left   => "Left",
                                       right  => "Right" },
                     columns      => 2 );


=head1 DESCRIPTION

Provides a radio group element class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4


=item values

A reference to an array of values for the select box.


=item labels

A reference to a hash mapping C<values> to display names.


=item columns

The number of columns in which you want your radio group to appear.
This defaults to 0, which indicates that radio buttons be put horizontally.


=back

=cut

1;
