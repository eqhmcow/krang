package PBMM::ocs_default_price;
use strict;
use warnings;
use base 'Krang::ElementClass::CheckBox';

sub input_form {
    my $self = shift;
    my %arg = @_;
    my $query = $arg{query};
    my $element = $arg{element};
    my $story = $element->story;

    # find the category default price
    my $category = $story->category;
    my $price;
    while($category and not defined $price) {
        if ($category->element->match('//default_price')) {
            $price = ($category->element->match('//default_price'))[0]->data;
        }
        $category = $category->parent;
    };
    
    my $no_price = defined $price ? 0 : 1;
    
    # get normal checkbox
    my $html = $self->SUPER::input_form(@_);

    # insert some javascript to update price and set it readonly when checked
    $html =~ s/<input/<input onchange="toggle_default_price(this)" /i;

    my ($targ) = $element->parent->child('price')->param_names;

    my $js = <<END;
<script language="javascript">
  function toggle_default_price(cb) {
      var form = cb.form;
      var e = form.elements['$targ'];
      if (cb.checked) {
        if ($no_price) {
          alert("No default price is set in the primary category for this story.");
          cb.checked = false;
        } else {
           e.value = '$price';
           e.readOnly = true;
           e.style.backgroundColor = '#DDDDDD';
        }
      } else {
        e.value = '';
        e.readOnly = false;
        e.style.backgroundColor = 'white';
      }
  }
</script>
END

    return $js . $html;
}

1;
