package Krang::ElementClass::Time;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass::Storable';
use Carp qw(croak confess);

use Time::Piece;

=head1 NAME

Krang::ElementClass::Time - A popup time chooser like the one used for cover_date

=head1 SYNOPSIS

  # in your element's new() method's %args hash's 'children' arrayref:
  sub new {
    my $pkg = shift;
    my %args = ( 
      name      => 'some_container', 
      children  => [
        ..., 
        pkg('ElementClass::Time')->new( 
          name          => 'my_time',
          min           => 1, 
          max           => 1, 
          reorderable   => 0,
          allow_delete  => 0,
          indexed       => 1,
          default       => Time::Piece->new + (60 * 60), # one hour from now
        ),
        ..,
        @_, 
      ],
    );
    return $self->SUPER::new(%args);
  }


=head1 DESCRIPTION

Provides time fields (hour minute and am/pm) combined into a single element.


=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.  The
data() field for elements of this class stores a Time::Piece object.

The XML format for the data of this element in an ISO-8601 date-time.

=cut

sub new {
    my $self = shift;
    my %args = (
        default => Time::Piece->new->strftime('%I:%M %p'),
        @_,
    );
    return $self->SUPER::new(%args);
}

sub default {
    my $self = shift;

    $self->{default} = shift if @_;

    if ($self->{default}) {
        return $self->{default};
    } else {
        return;
    }
}

sub input_form {
    my $self = shift;
    my %args = @_;

    my $query           = $args{query};
    my $element         = $args{element};
    my $xpath           = $element->xpath;
    my $datetime_object = $element->data;

    # use a simpler time widget (drop-downs not needed)
    my $html = Krang::Widget::time_chooser(
        name   => $xpath . '_time',
        query  => $query,
        hour   => $datetime_object->hour,
        minute => $datetime_object->minute,
    );

    return $html;
}

sub _fixup_time {
    my $self = shift;
    my $time = shift;
    $time = '' unless defined $time;

    $time =~ s/^\s+//;
    $time =~ s/\s+$//;

    # make sure AM & PM are uppercased
    $time = uc $time;

    # interpret empty and zero dates as 12am
    $time = '12:00 AM' if $time eq '' or ($time =~ /^\d+$/ and $time == 0);

    # add :00 to \d+ if time has no colons (minutes)
    $time =~ s/(\d+)/$1:00/ unless $time =~ /:/;

    #$time = "$1:00 $2" if $time =~ /^(\d+):? ([AP])M?$/;

    # accept a and p as 'am' and 'pm'
    $time =~ s/([AP])$/$1M/;

    $time .= ' PM' if $time =~ /^\d+:\d+$/;

    return $time;

}

sub load_query_data {
    my $self = shift;
    my %args = @_;

    my $query   = $args{query};
    my $element = $args{element};
    my $xpath   = $element->xpath();

    my $time = $query->param($xpath . '_time') || '';

    my $date = Time::Piece->new->ymd;
    $time = $self->_fixup_time($time);

    my $tp;
    eval { $tp = Time::Piece->strptime("$date $time", '%Y-%m-%d %I:%M %p') };
    confess(__PACKAGE__ . "->load_query_data() Error parsing time: $@") if $@;
    $element->data($tp);
}

sub param_names {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};
    my $xpath   = $element->xpath;
    return ($xpath . "_time");
}

sub validate {
    my $self = shift;
    my %args = @_;

    my $query   = $args{query};
    my $element = $args{element};
    my $xpath   = $element->xpath();

    my $time = $query->param($xpath . '_time');
    $time = $self->_fixup_time($time);

    # Check time part
    eval { Time::Piece->strptime($time, '%I:%M %p') };
    return (0, $self->{display_name} . ": Invalid time") if $@;

    return (1, undef);
}

sub index_data {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};

    return $element->data ? $element->data->strftime('%H:%M:%S') : '';
}

sub template_data {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};

    return ''
      unless $element
          and $element->data
          and ref($element->data)
          and UNIVERSAL::can($element->data, 'isa')
          and $element->data->can('strftime');

    return $element->data->strftime('%H:%M:%S');
}

sub view_data {
    my $self = shift;
    return $self->template_data(@_);
}

sub thaw_data_xml {
    my $self = shift;
    my %args = @_;

    my $element = $args{element};
    my $data    = $args{data}->[0];
    return undef unless $data;

    croak("Bad time format '$data' found during XML data parsing.")
      unless $data =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/;

    my $datetime = Time::Piece->strptime($data, '%Y-%m-%dT%H:%M:%SZ');

    return $element->data($datetime);
}

sub freeze_data_xml {
    my $self = shift;
    my %args = @_;

    my $element    = $args{element};
    my $xml_writer = $args{writer};

    my $data = $element->data;

    return $xml_writer->dataElement(data => '') unless $data;

    # build XML
    my $xml = $xml_writer->dataElement(data => $data->strftime('%Y-%m-%dT%H:%M:%SZ'),);

    return $xml;
}

1;
