package PBMM::ocs_price;
use strict;
use warnings;
use base 'PBMM::money';

sub input_form {
    my $self = shift;
    my %arg = @_;
    my $query = $arg{query};
    my $element = $arg{element};

    # get normal text box
    my $html = $self->SUPER::input_form(@_);

    # set readonly and grey if default is checked
    my $def = $element->parent->child('default');
    my $def_value = $query->param($def->param_names);
    $def_value = $def->data if not defined $def_value;
    if ($def_value) {
        $html =~ s!<input!<input readonly style="background-color: #DDDDDD" !i;
    }

    return $html;
}

1;
