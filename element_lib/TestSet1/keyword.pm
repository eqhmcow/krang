package TestSet1::keyword;
use strict;
use warnings;

=head1 NAME

TestSet1::keyword

=head1 DESCRIPTION

Example keyword element class for Krang.  This is just a set of 4 text
boxes where users can add keywords.  This element is bulk editable and
will create sets of 4 keywords from bulk edit data as needed.

=cut

use base 'Krang::ElementClass::Storable';
use Carp qw(croak);
use Krang::Log qw(debug);

use Krang::MethodMaker
  get_set => [ qw(
                  maxlength
                  size
                  fields ) ];

sub new {
   my $pkg = shift;
   my %args = ( name         => 'keyword', 
                display_name => 'Keywords',
                fields       => 4,
                size         => 24,
                maxlength    => 0,
                bulk_edit    => 1,
                @_
              );
   return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $param = $element->xpath;

    my $data = $element->data || [];
    while (@$data < $self->fields) {
        push(@$data, "");
    }
    
    my $index = 0;
    my @fields = 
      map { scalar $query->textfield(-name     => $param . '_' . $index++,
                                     -default  => $_,
                                     -size      => $self->size,
                                     ($self->maxlength ? 
                                      (-maxlength => $self->maxlength) :
                                      ())) 
        } @$data;

    my $html = join "\n",
      (map { '<div style="padding:2px">' . $_ . '</div>' } @fields);
    debug($html);
    return $html;
}

sub param_names {
    my $self = $_[0];
    my $element = $_[2];
    my $param = $element->xpath();
    my $fields = $self->fields;
    $fields = @{$element->data} 
      if $element->data and @{$element->data} > $fields;
    return map { $param . "_" . $_ } (0 .. $fields - 1);
}

sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $param = $element->xpath;
    $element->data([grep { length $_ } 
                      map { $query->param($_) } 
                        sort 
                          grep { /^\Q$param\E/ } $query->param()]);
    $query->delete($_) for grep { /^\Q$param\E/ } $query->param();
}


sub view_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    return "" unless $element->data;
    return join(', ', map { CGI->escapeHTML($_) } @{$element->data});
}

sub bulk_edit_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    return $element->data ? @{$element->data} : ();
}

sub bulk_edit_filter {
    my ($self, %arg) = @_;
    my ($data) = @arg{qw(data)};
    my @data = @$data;
    my @return;
    while(@data) {
        if (@data > $self->fields) {
            push(@return, [ map { shift(@data) } (1 .. $self->fields) ]);
            next;
        } else {
            push(@return, [ @data ]);
            last;
        }
    }
    return @return;
}

# return all keywords for indexing
sub index_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    my $data = $element->data;
    return @$data if $data;
    return ();
}

1;
