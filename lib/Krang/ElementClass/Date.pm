package Krang::ElementClass::Date;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass::Storable';
use Carp qw(croak);

use Krang::ClassLoader MethodMaker => 
  get_set => [ qw( size maxlength start_year end_year ) ];
use Time::Piece;

sub new {
    my $pkg = shift;
    my %args = ( 
                start_year => localtime()->year - 30,
                end_year => localtime()->year + 10,
                @_
               );
    
    return $pkg->SUPER::new(%args);
}

sub default {
    my $self = shift;
    $self->{default} = shift if @_;
    return $self->{default} if $self->{default};
    return Time::Piece->new();
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $date = $element->data();
    return $self->_date_input($query, $element->xpath, $date);
}

sub param_names { 
    my $element = $_[2];
    my $xpath = $element->xpath;
    return ($xpath . "_month", $xpath . "_day", $xpath . "_year");
}

sub validate {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $param = $element->xpath();

    my $m = $query->param($param . '_month');
    my $d = $query->param($param . '_day');
    my $y = $query->param($param . '_year');

    if (not $m and not $d and not $y) {
        if ($self->{required}) {
            return (0, "$self->{display_name} requires a value.");
        } else {
            return (1, undef);
        }
    } elsif ($m and $d and $y) {
        return (1, undef);
    } elsif ($m or $d or $y) {
        return (0, "$self->{display_name} selection incomplete.");
    }

    return (1, undef);
}

sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $param = $element->xpath;

    my $m = $query->param($param . '_month');
    my $d = $query->param($param . '_day');
    my $y = $query->param($param . '_year');
    if ($m and $d and $y) {
        $element->data(Time::Piece->strptime("$m/$d/$y", '%m/%d/%Y'));
    } else {
        $element->data(undef);
    }
}

sub view_data {
    my $element = $_[2];
    return "" unless $element->data;
    return $element->data->mdy("/");
}

# takes a name and an optional date object (Time::Piece::MySQL).
# returns HTML for the widget interface.
sub _date_input {
    my ($self, $query, $name, $date) = @_;

    my $m_sel = $query->popup_menu(-name      => $name . "_month",
                                   -default   => $date ? $date->mon : 0,
                                   -values    => [ '', 1 .. 12 ],
                                   -labels    => { ''  => ' ',
                                                   1  => 'Jan',
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
                                   -default   => $date ? $date->mday : 0,
                                   -values    => [ '', 1 .. 31 ],
                                   -labels    => { '' => ' ' },
                                  );
    my $y_sel = $query->popup_menu(-name      => $name . "_year",
                                   -default   => $date ? $date->year : 0,
                                   -values    => [ '', 
                                                   $self->start_year ..
                                                   $self->end_year ],
                                   -labels    => { '' => ' ' });


    return $m_sel . "&nbsp;" . $d_sel . "&nbsp;" . $y_sel;
}

sub fill_template {
    my ($self, %arg) = @_;
    $arg{tmpl}->param($self->name, $self->template_data(%arg));
}

sub template_data {
    my ($self, %arg) = @_;
    return "" unless $arg{element}->data;
    $arg{element}->data->strftime('%b %e, %Y')
} 

sub thaw_data_xml {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    my ($data) = $arg{qw(data)}->[0];
    return undef unless $data;

    croak("Bad date format '$data' found during XML data parsing.")
      unless $data =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/;

    my $format = "%Y-%m-%dT%H:%M:%SZ";
    my $time = Time::Piece->strptime($data,$format);

    # adjust for timezone
    $time -= $time->tzoffset;

    return $element->data($time);
}

sub freeze_data_xml {
    my ($self, %arg) = @_;
    my ($element, $writer) = @arg{'element', 'writer'};
    my $data = $element->data;
    return $writer->dataElement(data => '') unless $data;
    
    # adjust for timezone
    $data += $data->tzoffset;

    # build XML
    my $xml = $writer->dataElement(data => 
                                   $data->strftime("%Y-%m-%dT%H:%M:%SZ"));
    
    # undo adjustment
    $data -= $data->tzoffset;

    return $xml;
}






=head1 NAME

Krang::ElementClass::Date - date element class

=head1 SYNOPSIS

  $class = pkg('ElementClass::Date')->new(name         => "issue_date",
                                          default      => Time::Piece->new(),
                                          start_year   => 1990,
                                          end_year     => 2020);

=head1 DESCRIPTION

Provides a date field element class.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.  The
data() field for elements of this class stores a Time::Piece object.

The XML format for the data of this element in an ISO-8601 date-time
like:

  2004-10-01T12:53:01Z

The date must be expressed in UTC with the timezone specifier "Z".  It
will be transformed into local-time when loaded.

=cut

1;
