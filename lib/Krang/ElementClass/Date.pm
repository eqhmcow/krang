package Krang::ElementClass::Date;
use strict;
use warnings;

use base 'Krang::ElementClass::Storable';

use Krang::MethodMaker
  get_set => [ qw( size maxlength ) ];
use Time::Piece;

sub new {
    my $pkg = shift;
    my %args = ( @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $date = $element->data() || Time::Piece->new();
    return _date_input($query, $param, $date);
}

sub param_names { 
    my $element = $_[2];
    my $xpath = $element->xpath;
    return ($xpath . "_month", $xpath . "_day", $xpath . "_year");
}

sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $data = _decode_date($query, $param);
    $element->data($data);
}

sub view_data {
    my $element = $_[2];
    return "" unless $element->data;
    return $element->data->mdy("/");
}

# takes a name and an optional date object (Time::Piece::MySQL).
# returns HTML for the widget interface.  If no date is passed
# defaults to now.
sub _date_input {
    my ($query, $name, $date) = @_;
    $date ||= localtime;

    my $m_sel = $query->popup_menu(-name      => $name . "_month",
                                   -default   => $date->mon,
                                   -values    => [ 1 .. 12 ],
                                   -labels    => { 1  => 'Jan',
                                                   2  => 'Feb',
                                                   3  => 'Mar',
                                                   4  => 'Apr',
                                                   5  => 'May',
                                                   6  => 'Jun',
                                                   7  => 'Jul',
                                                   8  => 'Aug',
                                                   9  => 'Sep',
                                                   10 => 'Oct',
                                                   11 => 'Nov',
                                                   12 => 'Dec' });
    my $d_sel = $query->popup_menu(-name      => $name . "_day",
                                   -default   => $date->mday,
                                   -values    => [ 1 .. 31 ]);
    my $y_sel = $query->popup_menu(-name      => $name . "_year",
                                   -default   => $date->year,
                                   -values    => [ $date->year - 30 .. 
                                                   $date->year + 10 ]);


    return $m_sel . " " . $d_sel . " " . $y_sel;
}

# decode a date from query input.  Takes a form name, returns a date
# object.
sub _decode_date {
    my ($query, $name) = @_;
    
    my $m = $query->param($name . '_month');
    my $d = $query->param($name . '_day');
    my $y = $query->param($name . '_year');
    return undef unless $m and $d and $y;

    return Time::Piece->strptime("$m/$d/$y", '%m/%d/%Y');
}


sub fill_template {
    my ($self, %arg) = @_;
    $arg{tmpl}->param($self->name, 
                      $arg{element}->data->strftime('%b %e, %Y'))
      if $arg{element}->data;
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
