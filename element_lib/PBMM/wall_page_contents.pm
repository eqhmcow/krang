package PBMM::wall_page_contents;
use strict;
use warnings;

=head1 NAME

PBMM::wall_page_contents - widget to control what gets displayed on the wall page

=cut

use base 'Krang::ElementClass::Storable';

sub new {
   my $pkg = shift;

   my %args = ( name         => 'wall_page_contents',
                display_name => 'Wall Page Contents',
                min          => 1,
                max          => 1,
                allow_delete => 0,
                reorderable  => 0,
                default      => {which => 'paragraph', 
                                 num   => 2},
                @_);

   return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $data = $element->data();

    my ($para_radio, $abs_radio) = 
      $query->radio_group(-name      => $param . "_which",
                          -default   => $data->{which},
                          -values    => [ 'paragraph',
                                          'abstract' ],
                          -labels    => { paragraph => 'By Paragraph',
                                          abstract  => 'By Abstract',
                                        },
                                   );
    my $para_num = $query->textfield(-name => $param . "_num",
                                     -default   => $data->{num} || '2',
                                     -size      => 4);
    my $abs_text = $query->textarea(-name     => $param . "_abs",
                                    -default  => $data->{abs} || "",
                                    -rows     => 4
                                    -cols     => 30);
    return "$para_radio : $para_num <br> $abs_radio :<br>$abs_text";
}

sub validate {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $which = $query->param($param . "_which");
    my $num = $query->param($param . "_num");
    my $abs = $query->param($param . "_abs");

    if ($which eq 'paragraph') {
        if (not defined $num or not length $num or $num !~ /^[1-9]\d*$/) {
            return (0, "Wall page contents 'By Paragraph' ".
                       "requires a number of paragraphs.");
        }
    } elsif ($which eq 'abstract') {
        if (not defined $abs or not length $abs) {
            return (0, "Wall page contents 'By Abstract' ".
                       "requires abstract text.");
        }
    }

    return 1;
}

sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $which = $query->param($param . "_which");
    my $num = $query->param($param . "_num");
    my $abs = $query->param($param . "_abs");

    $element->data({ which => $which,
                     num   => $num,
                     abs   => $abs });
}

1;
