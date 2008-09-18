package Krang::ElementClass::DateTime;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass::Storable';
use Carp qw(croak);

use Krang::ClassLoader MethodMaker => get_set => [ qw( start_year end_year ) ];
use Time::Piece;

=head1 NAME

Krang::ElementClass::DateTime - An element like the cover_date inputs

=head1 SYNOPSIS

  # in your element's new() method's %args hash's 'children' arrayref:
  sub new {
    my $pkg = shift;
    my %args = ( 
      name      => 'some_container', 
      children  => [
        ..., 
        pkg('ElementClass::DateTime')->new( 
          name          => 'my_date_time',
          min           => 1, 
          max           => 1, 
          reorderable   => 0,
          allow_delete  => 0,
          indexed       => 1,
          default       => Time::Piece->new->year, # now
          start_year    => 2004,
          end_year      => Time::Piece->new->year + 1,
        ),
        ..,
        @_, 
      ],
    );
    return $self->SUPER::new(%args);
  }


=head1 DESCRIPTION

Provides date and time fields combined into a single element.


=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.  The
data() field for elements of this class stores a Time::Piece object.

The XML format for the data of this element in an ISO-8601 date-time.

=cut


sub new {
  my $self = shift;
  my %args = ( 
    start_year  => Time::Piece->new->year - 10,
    end_year    => Time::Piece->new->year + 10,
    default     => Time::Piece->new,
    @_,
  );
  return $self->SUPER::new(%args);
}

sub default {
  my $self = shift;

  $self->{default} = shift if @_;

  if ($self->{default}) {
    return $self->{default};
  } 
  else {
    return;
  }
}

sub input_form {
  my $self = shift;
  my %args = @_;

  my $query = $args{query};
  my $element = $args{element};
  my $xpath = $element->xpath;
  my $datetime_object = $element->data;
  
  my $html = Krang::Widget::date_chooser(
    name  => $xpath . '_date',
    query => $query, 
    date  => $datetime_object,
  );
  
  # add a simpler time widget (drop-downs not needed)
  $html .= ' &nbsp; ';

  $html .= Krang::Widget::time_chooser(
    name    => $xpath . '_time',
    query   => $query, 
    hour    => $datetime_object->hour,
    minute  => $datetime_object->minute,
  );

  return $html
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

  my $query = $args{query};
  my $element = $args{element};
  my $xpath = $element->xpath();

  my $date = $query->param($xpath . '_date');
  my $time = $query->param($xpath . '_time') || '';

  $time = $self->_fixup_time($time);
  
  if ($date) {
      $element->data(Time::Piece->strptime("$date $time", '%m/%d/%Y %I:%M %p'));
  } else {
      $element->data(undef);
  }
}

sub param_names { 
  my $self = shift;
  my %args = @_;
  
  my $element = $args{element};
  my $xpath = $element->xpath;
  return ($xpath . "_date", $xpath . "_time");
}

sub validate {
  my $self = shift;
  my %args = @_;
  
  my $query = $args{query};
  my $element = $args{element};
  my $xpath = $element->xpath();

  my $date = $query->param($xpath . '_date');
  my $time = $query->param($xpath . '_time');
  
  # Check the date part first (so we can report the error better
  eval {Time::Piece->strptime($date, '%m/%d/%Y') };
  return (0, $self->{display_name} . ": Invalid date") if $@;
  
  $time = $self->_fixup_time($time);

  # Check time part
  eval {Time::Piece->strptime($time, '%I:%M %p') };
  return (0, $self->{display_name} . ": Invalid time") if $@;

  return (1, undef);
}

sub index_data {
  my $self = shift;
  my %args = @_;

  my $element = $args{element};
    
  return $element->data ? $element->data->strftime('%Y-/%m-/%d %H:%M:%S') : '';
}

sub template_data {
  my $self = shift;
  my %args = @_;

  my $element = $args{element};

  return '' unless $element
    and $element->data
    and ref($element->data)
    and UNIVERSAL::can($element->data, 'isa')
    and $element->data->can('strftime');

  return $element->data->strftime('%A, %B %e, %Y');
}

sub view_data {
  my $self = shift;
  return $self->template_data(@_);
}

sub thaw_data_xml {
  my $self = shift;
  my %args = @_;

  my $element = $args{element};
  my $data = $args{data}->[0];
  return undef unless $data;

  croak("Bad datetime format '$data' found during XML data parsing.")
    unless $data =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/;

  my $datetime = Time::Piece->strptime($data, '%Y-%m-%dT%H:%M:%SZ');

  return $element->data($datetime);
}

sub freeze_data_xml {
  my $self = shift;
  my %args = @_;

  my $element = $args{element};
  my $xml_writer = $args{writer};

  my $data = $element->data;
  
  return $xml_writer->dataElement(data => '') unless $data;
    
  # build XML
  my $xml = $xml_writer->dataElement(
    data => $data->strftime('%Y-%m-%dT%H:%M:%SZ'),
  );
    
  return $xml;
}

1;
