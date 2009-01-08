package Krang::ElementClass::TextInputList;
use strict;
use warnings;

use Krang::ClassFactory qw(pkg);

use Krang::ClassLoader base => 'ElementClass';
use Krang::ClassLoader Log  => qw(critical debug);

use Krang::ClassLoader MethodMaker => get_set => [qw( size maxlength)];

sub new {
    my $pkg  = shift;
    my %args_in = @_;

    my %function_for = ();
    my $bulk_edit_tag = $args_in{bulk_edit_tag} || '';

    if ($bulk_edit_tag && ($bulk_edit_tag eq 'ul' or $bulk_edit_tag eq 'ol')) {
        $function_for{before_bulk_edit} = $args_in{before_bulk_edit}
          || $pkg->before_bulk_edit_dispatch(tag => $args_in{bulk_edit_tag});

        $function_for{before_bulk_save} = $args_in{before_bulk_save}
          || $pkg->before_bulk_save_dispatch(tag => $args_in{bulk_edit_tag});
    }

    my %args = (
        name => 'text_input_list',
        size => 40,
        maxlength => 0,
        @_,
        %function_for,
    );

    return $pkg->SUPER::new(%args);
}

sub before_bulk_edit_dispatch {
    my ($self, %args) = @_;

    if ($args{tag} eq 'ul' or $args{tag} eq 'ol') {
        return sub {
            my (%args) = @_;
            return join('', map {"<li>$_</li>"} @{$args{element}->data});
        }
    }
    croak(__PACKAGE__ . "::before_bulk_edit_dispatch() - Unsupported bulk edit tag '$args{tag}'");
}

sub before_bulk_save_dispatch {
    my ($self, %args) = @_;

    if ($args{tag} eq 'ul' or $args{tag} eq 'ol') {
        return sub {
            my (%args) = @_;
            my $sep = $args{element}->class->field_separator;
            my $data = $args{data};
            # chop leading   <li>
            $data =~ s/^<li[^>]*>//smi;
            # chop trailing </li>
            $data =~ s/<\/li[^>]*>$//smi;
            # split on </li><li>, allowing for LI attribs and whitespace
            return [ split(/<\/li[^>]*>\s*<li[^>]*>/smi, $data) ];
        }
    }
    croak(__PACKAGE__ . "::before_bulk_save_dispatch() - Unsupported bulk edit tag '$args{tag}'");
}

sub input_form {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $separator = $self->field_separator();

    # the list items
    my @data = @{ $element->data || [] };

    my $size             = $self->size;
    my $maxlength        = $self->maxlength;
    my $size_attrib      = ' size="' . $size . '"';
    my $maxlength_attrib = $maxlength ? (' maxlength="' . $maxlength . '"') : '';

    # starting the container DIV
    my $html = qq{<div id="${param}_container" class="krang-elementclass-textinputlist">};

    # the first
    my $first = shift(@data);
    $first    = '' unless defined($first);

    # maybe the last
    my $last = pop(@data);
    $last    = '' unless defined($last);
    my $first_style = $last ? '' : 'style="display: none;"';

    # add first input field with buttons to add, delete, maybe push-down
    $html .=<<END;
<div>
  <input type="text"   name="${param}_0"    value="$first" $size_attrib $maxlength_attrib/><input type="button" name="item_add"                  value="+" class="krang-elementclass-textinputlist-button" /><input type="button" $first_style name="item_delete"   value="&#x2212;" class="krang-elementclass-textinputlist-button"/><input type="button" $first_style name="item_down"     value="&#x2193;" class="krang-elementclass-textinputlist-button"/><input type="button" style="display: none;" name="item_up"     value="&#x2191;" class="krang-elementclass-textinputlist-button"/>
</div>
END

    # add the others
    my $cnt = 1;
    for my $field_text (@data) {
        $html .=<<END;
<div>
  <input type="text"   name="${param}_$cnt" value="$field_text" $size_attrib $maxlength_attrib/><input type="button" name="item_add"      value="+" class="krang-elementclass-textinputlist-button"/><input type="button" name="item_delete"   value="&#x2212;" class="krang-elementclass-textinputlist-button"/><input type="button" name="item_down"     value="&#x2193;" class="krang-elementclass-textinputlist-button"/><input type="button" name="item_up"       value="&#x2191;" class="krang-elementclass-textinputlist-button"/>
</div>
END
        $cnt++;
    }

    # add the last
    if ($last) {
        $html .=<<END;
<div>
  <input type="text"   name="${param}_$cnt" value="$last" $size_attrib $maxlength_attrib/><input type="button" name="item_add"      value="+" class="krang-elementclass-textinputlist-button"/><input type="button" name="item_delete"   value="&#x2212;" class="krang-elementclass-textinputlist-button"/><input type="button" style="display: none;" name="item_down"     value="&#x2193;" class="krang-elementclass-textinputlist-button"/><input type="button" name="item_up"       value="&#x2191;" class="krang-elementclass-textinputlist-button"/>
</div>
END
    }

    # close container
    $html .= '</div>';

    # put the concatenated data into the hidden field used to return the data
    my $field_sep = $self->field_separator;
    my $data      = join($field_sep, @data);
    $html        .= qq{<input type="hidden" id="$param" name="$param" value="$data" />};

    # JavaScript init code: add only once
    my @sibs = grep { $_->class->isa(__PACKAGE__) } $element->parent()->children();
    if ($sibs[0]->xpath() eq $element->xpath()) {
        $html .= $self->add_javascript();
    }

    # for each element add click handler and save-hook JavaScript
    $html .=<<END;
<script type="text/javascript">
// call just before saving to backend
Krang.ElementEditor.add_save_hook(function() {
    Krang.ElementClass.TextInputList.onSave("$param");
});

// attach click handler to container
\$("${param}_container").observe('click', Krang.ElementClass.TextInputList.clickHandler);

// pass the size and maxlength values through
Krang.ElementClass.TextInputList["$param"] = [];
Krang.ElementClass.TextInputList["$param"]["size"] = $size;
Krang.ElementClass.TextInputList["$param"]["maxlength"] = $maxlength;
</script>
END

    return $html;
}

sub add_javascript {
    my ($self) = @_;

    my $field_sep = $self->field_separator;

    return <<END;
<script type="text/javascript">
if (typeof Krang.ElementClass == 'undefined') {
    Krang.ElementClass = {};
}

Krang.ElementClass.TextInputList = {
    clickHandler : function(event) {
        var target = Event.element(event);
        var item   = target.up();
        if (target.name) {
            var func = Krang.ElementClass.TextInputList[target.name];
            if (Object.isFunction(func)) {
                func(item);
            }
        }
    }.bindAsEventListener({}),

    functionFor : {
        '+'       : 'item_add',
        '\\u2212' : 'item_delete',
        '\\u2193' : 'item_down',
        '\\u2191' : 'item_up'
    },

    item_add : function(currItem) {

        var hidden    = currItem.up().next();
        param         = hidden.id;
        var size      = Krang.ElementClass.TextInputList[param]["size"];
        var maxlength = Krang.ElementClass.TextInputList[param]["maxlength"];

        var newItem = new Element('div');
        var newText = new Element('input', {type : 'text', size : size});
        if (maxlength != 0) {
           newText.writeAttribute('maxlength', maxlength);
        }
        newText.identify();
        newItem.appendChild(newText);
        ['+', '\\u2212', '\\u2193', '\\u2191'].each(function(btn) {
                newItem.appendChild(new Element('input',
                     {type : 'button', value : btn, name : Krang.ElementClass.TextInputList.functionFor[btn],
                      'class' : "krang-elementclass-textinputlist-button"}));


            });

        currItem.insert({after : newItem});

        // anyway show DELETE and DOWN button on current item
        currItem.down().next(1).show().next().show();

        if (Krang.ElementClass.TextInputList.isLast(newItem)) {
            // hide DOWN button on new item
            newItem.down().next(2).hide();
        }

        // focus new text input
        newText.focus();
    },

    item_delete : function(currItem) {
        var nextItem = currItem.next();
        var prevItem = currItem.previous();

        siblings = currItem.siblings();

        // remove it
        currItem.remove();

        if (siblings.length == 1) {
            siblings[0].down().next(1).hide().next().hide().next().hide();
            return currItem;
        }

        if (nextItem && Krang.ElementClass.TextInputList.isFirst(nextItem)) {
            // show DOWN, hide UP button on future first item
            nextItem.down().next(2).show().next().hide();
        }

        if (prevItem && Krang.ElementClass.TextInputList.isLast(prevItem)) {
            // hide DOWN, show UP button on future last item
            prevItem.down().next(2).hide().next().show();
        }

        return currItem;
    },

    item_down : function(currItem) {
        var nextItem = currItem.next();
        // insert it after its next sibling
        nextItem.insert({after : currItem.remove()});
        // on moved down element...
        if (Krang.ElementClass.TextInputList.isLast(currItem)) {
            // ... hide DOWN button ...
            currItem.down().next(2).hide();
        }
        // ... and show UP button
        currItem.down().next(3).show();
        // on next element ...
        if (Krang.ElementClass.TextInputList.isFirst(nextItem)) {
            // ... hide UP button ...
            nextItem.down().next(3).hide();
        }
        // ... and show DOWN button
        nextItem.down().next(2).show();
    },

    item_up : function(currItem) {
        var prevItem = currItem.previous();
        // insert it before its previous sibling
        prevItem.insert({before : currItem.remove()});
        // on moved up element...
        if (Krang.ElementClass.TextInputList.isFirst(currItem)) {
            // ... hide UP button ...
            currItem.down().next(3).hide();
        }
        // ... and show DOWN button
        currItem.down().next(2).show();
        // on previous ...
        if (Krang.ElementClass.TextInputList.isLast(prevItem)) {
            // ... hide DOWN button ...
            prevItem.down().next(2).hide();
        }
        // ... and  show UP button
        prevItem.down().next(3).show();
    },

    isFirst : function(item) {
        return ! item.previous();
    },

    isLast : function(item) {
        return ! item.next();
    },

    onSave : function(param) {
        var cnt = 0;
        var children = \$(param+'_container').childElements();
        var returnElement = \$(param);
        var returnValues = children.inject([], function(acc, item) {
            var textField = item.down();
            if (textField) {
                acc.push(textField.value);
            }
            return acc;
        });
        returnElement.value = returnValues.join("$field_sep");
    }
};
</script>
END
}

sub load_query_data {
    my ($self,  %args)    = @_;
    my ($query, $element) = @args{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    my $cnt = 0;
    my $raw = $query->param($param);
    my $sep = $self->field_separator;

    my @data = $raw ? split(/$sep/, $raw) : ();

    $element->data(\@data);
}

# we override this method so that it won't escape the HTML
sub view_data {
    my ($self,    %arg)  = @_;
    my ($element, $data) = @arg{qw(element data)};

    return join('<br/>', @$data);
}

sub fill_template {
    my ($self, %args) = @_;
    my ($element, $tmpl, $publisher) = @args{ qw(element tmpl publisher) };

    my $name      = $element->name;
    my $loop_name = $name . '_loop';
    my $item_name = $name . '_item';
    my @data      = @{ $element->data || [] };

    $tmpl->param($loop_name => [ map { {$item_name => $_} } @data ]);
}

sub freeze_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    my $data    = $element->data || [];
    my $sep     = $self->field_separator();
    return join($sep, @$data);
}

sub thaw_data {
    my ($self,    %arg)  = @_;
    my ($element, $data) = @arg{qw(element data)};

    if ($data) {
        my $sep = $self->field_separator();
        return $element->data([split(/\Q$sep/, $data)]);
    } else {
        return $element->data([]);
    }
}

sub field_separator { return "\x{E000}" }

=head1 NAME

Krang::ElementClass::TextInputList - a manageable list of text input fields

=head1 SYNOPSIS

   $class = pkg('ElementClass::TextInputList')->new(
        name => "keywords",
        maxlength => 10,
        size      => 12,
   );

   $class = pkg('ElementClass::TextInputList')->new(
        name          => "unordered_list",
        bulk_edit     => 'xinha',
        bulk_edit_tag => 'ul',
   );

=head1 DESCRIPTION

This element provides a list of one or more text input fields
that can be added, deleted and moved up and down.

It may be used to represent HTML ordered and unordered lists, each
list item being represented by one text input field. This also
provides for more orthogonality with Xinha-based bulk editing.
Un(ordered) lists edited in Xinha bulk edit can be mapped to a
TextInputList element as shown in the SYNOPSIS. Indeed, 'ul' and 'ol'
are the only supported values for B<bulk_edit_tag>

Another use-case would be a list of keywords, also shown in the
SYNOPSIS. Textarea-based bulk-editing is currently not supported.

The data slot holds an arrayref of the list element values.

C<fill_template()> generates a tmpl_loop whose naming convention is
best explained with an example.

   $class = pkg('ElementClass::TextInputList')->new(
        name => "keywords",
   );

yields

   <tmpl_loop keywords_loop>
     <tmpl_var keywords_item>
   </tmpl_loop>

appending '_loop' resp. '_item' to the element's name.


=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available.

=over 4

=item size

The size of the text box on the edit screen.  Defaults to 30.

=item maxlength

The maximum number of characters the user will be allowed to enter.
Defaults to 0, meaning no limit.

=back


=cut

1;
