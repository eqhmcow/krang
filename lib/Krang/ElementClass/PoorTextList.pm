package Krang::ElementClass::PoorTextList;
use strict;
use warnings;

use Krang::ClassFactory qw(pkg);

use Krang::ClassLoader base => 'ElementClass::_PoorTextBase';

use Krang::ClassLoader Log => qw(debug);

use Digest::MD5 qw(md5_hex);
use Carp qw(croak);

# For *Link hard find feature
use Storable qw(nfreeze);
use MIME::Base64 qw(encode_base64);

use Krang::ClassLoader MethodMaker => get_set => [qw( defaults )];

sub new {
    my $pkg = shift;

    my %args_in = @_;

    my %function_for = ();
    my $bulk_edit_tag = $args_in{bulk_edit_tag} || '';

    if ($bulk_edit_tag && ($bulk_edit_tag eq 'ul' or $bulk_edit_tag eq 'ol')) {
        $function_for{before_bulk_edit} = $args_in{before_bulk_edit}
          || $pkg->before_bulk_edit_dispatch(tag => $args_in{bulk_edit_tag});

        $function_for{before_bulk_save} = $args_in{before_bulk_save}
          || $pkg->before_bulk_save_dispatch(tag => $args_in{bulk_edit_tag});
    }

    my %arg = (
        width  => 300,
        height => 140,    # for 'textarea' flavour. For 'text' flavour see poortext.css '.pt-text'
        command_button_bar => 1,
        special_char_bar   => 0,
        commands           => 'basic_with_special_chars',
        find               => '',
        defaults           => [],
        @_,
        %function_for,
    );

    # validate commands spec
    my $command_spec = $pkg->command_spec();
    if ($arg{commands}) {
        if (ref($arg{commands})) {
            croak(  __PACKAGE__
                  . "::new() - 'commands' option must be string or arrayref, but is "
                  . ref($arg{commands}))
              if ref($arg{commands}) ne 'ARRAY';
        } elsif (!exists $command_spec->{$arg{commands}}) {
            croak("\"$arg{commands}\" is not a known set of commands");
        }
    }

    return $pkg->SUPER::new(%arg);
}

sub before_bulk_edit_dispatch {
    my ($self, %args) = @_;

    if ($args{tag} eq 'ul' or $args{tag} eq 'ol') {
        return sub {
            my (%args) = @_;
            return join('', map { "<li>$_</li>" } @{$args{element}->data});
          }
    }
    croak(__PACKAGE__ . "::before_bulk_edit_dispatch() - Unsupported bulk edit tag '$args{tag}'");
}

sub before_bulk_save_dispatch {
    my ($self, %args) = @_;

    if ($args{tag} eq 'ul' or $args{tag} eq 'ol') {
        return sub {
            my (%args) = @_;
            my $sep    = $args{element}->class->field_separator;
            my $data   = $args{data};

            # chop leading   <li>
            $data =~ s/^<li[^>]*>//smi;

            # chop trailing </li>
            $data =~ s/<\/li[^>]*>$//smi;

            # split on </li><li>, allowing for LI attribs and whitespace
            return [split(/<\/li[^>]*>\s*<li[^>]*>/smi, $data)];
          }
    }
    croak(__PACKAGE__ . "::before_bulk_save_dispatch() - Unsupported bulk edit tag '$args{tag}'");
}

sub mark_form_invalid {
    my ($self, %arg) = @_;
    my ($html) = @arg{qw(html)};
    return qq{<div style="border-left: 3px solid #ffffac">$html</div>};
}

sub validate { 1 }

sub load_query_data {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    # the HTML
    my $html = $query->param($param);

    debug(__PACKAGE__ . "->load_query_data($param) - HTML coming from the browser: " . $html);

    # fix the markup
    if ($html) {
        $html = pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->browser2db(html => $html);

        debug(__PACKAGE__ . "->load_query_data($param) - HTML sent to DB: " . $html);
    }

    my $sep = $self->field_separator;
    $element->data([split(/$sep/, $html)]);
}

sub input_form {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    # the returned HTML
    my $html = "";

    # data has multiple fields
    my @data = @{$element->data || []};

    unless (@data) {
        my $defaults = $self->defaults;
        @data =
            $defaults
          ? (ref($defaults) and ref($defaults) eq 'ARRAY')
              ? @{$defaults}
              : (('') x $defaults)
          : ();
    }

    # get some setup stuff
    my $config          = $self->get_pt_config(%arg, has_content => $data[0]);
    my $class           = $self->get_css_class(%arg);
    my $style           = $self->get_css_style(%arg);
    my $not_first_style = $style;
    my $button_class    = 'krang-elementclass-poortextlist-button';
    my $item_style      = "height: 2.5em";

    # type dependant CSS
    if ($self->type eq 'textarea') {
        $not_first_style .= ' margin-top: 3px';
        $button_class = 'krang-elementclass-poortextlist-button-top-margin';
        $item_style   = '';
    }

    # JavaScript init code: add only once
    my @sibs = grep { $_->class->isa(__PACKAGE__) } $element->parent()->children();
    if ($sibs[0]->xpath() eq $element->xpath()) {

        # I''m the first!  Insert one-time JavaScript
        $html .= $self->get_one_time_javascript(%arg);
    }

    # starting the overall container DIV
    $html .= qq{<div id="${param}_container" class="krang-elementclass-poortextlist">};

    # the first
    my $first_data = shift(@data);
    $first_data = '' unless defined($first_data);

    # maybe the last
    my $last_data = pop(@data);

    # add first item
    my $text = pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->db2browser(html => $first_data);
    my @text = ($text);
    $html .= $self->add_item(
        param            => $param,
        cnt              => 0,
        text             => $text,
        config           => $config,
        class            => $class,
        style            => $style,
        down_btn_style   => (defined($last_data) ? '' : 'style="display: none;"'),
        up_btn_style     => 'style="display: none;"',
        delete_btn_style => (defined($last_data) ? '' : 'style="display: none;"'),
        button_class     => 'krang-elementclass-poortextlist-button',
        item_style       => $item_style,
    );

    # add the others
    my $cnt = 1;
    for my $middle_data (@data) {
        my $text = pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->db2browser(html => $middle_data);
        push @text, $text;
        $html .= $self->add_item(
            param            => $param,
            cnt              => $cnt,
            text             => $text,
            config           => $config,
            class            => $class,
            style            => $not_first_style,
            down_btn_style   => '',
            up_btn_style     => '',
            delete_btn_style => '',
            button_class     => $button_class,
            item_style       => $item_style,
        );
        $cnt++;
    }

    # add the last
    if (defined($last_data)) {
        my $text = pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->db2browser(html => $last_data);
        push @text, $text;
        $html .= $self->add_item(
            param            => $param,
            cnt              => $cnt,
            text             => $text,
            config           => $config,
            class            => $class,
            style            => $not_first_style,
            down_btn_style   => 'style="display: none;"',
            up_btn_style     => '',
            delete_btn_style => '',
            button_class     => $button_class,
            item_style       => $item_style,
        );
    }

    # close container
    $html .= '</div>';

    # data store for this element
    $cnt++;
    $html .= <<END;
<script type="text/javascript">
// data store for this element
Krang.ElementClass.PoorTextList["$param"] = {
    className        : "$class",
    style            : "$not_first_style",
    buttonClass      : "$button_class",
    ptConfig         : $config,
    nextItemNumber   : $cnt,
    itemStyle        : "$item_style"
}
</script>
END

    # put the concatenated data into the hidden field used to return the data
    # !! escape single quotes and enclose $data in single quotes !!
    my $sep = $self->field_separator;
    my $data = join($sep, @text);
    $data =~ s/'/&#39;/g;
    $html .= qq{<input type="hidden" id="$param" name="$param" value='$data' />};

    # Add hard find parameters
    my $find = encode_base64(nfreeze(scalar($self->find())));
    $html .= $query->hidden("hard_find_$param", $find);

    # for each element add click handler and save-hook JavaScript
    $html .= <<END;
<script type="text/javascript">
// call just before saving to backend
Krang.ElementEditor.add_save_hook(function() {
    Krang.ElementClass.PoorTextList.onSave("$param");
});

// attach click handler to container
\$("${param}_container").observe('click', Krang.ElementClass.PoorTextList.clickHandler);
</script>
END
    return $html;
}

sub add_item {
    my ($self, %arg) = @_;

    my $html = '';

    # pt field id
    my $id = "$arg{param}_$arg{cnt}";

    # create the edit area DIV and ...
    return <<END;
<div class="$id poortextlist_item" style="$arg{item_style}">
  <div class="$arg{class}" style="$arg{style}" id="$id">$arg{text}</div><input type="button" name="item_add" value="+" class="$arg{button_class}" /><input type="button" $arg{delete_btn_style} name="item_delete"   value="&#x2212;" class="$arg{button_class}"/><input type="button" $arg{down_btn_style} name="item_down"     value="&#x2193;" class="$arg{button_class}"/><input type="button" $arg{up_btn_style} name="item_up"     value="&#x2191;" class="$arg{button_class}"/>
</div>

<script type="text/javascript">
    // configure this element
    Krang.PoorTextCreationArguments.push(["$id", "$arg{param}", $arg{config}]);
</script>
END
}

sub view_data {
    my ($self, %arg) = @_;

    my @data = @{$arg{element}->data || []};
    return scalar(@data) ? join("<br/>", @data) : '';
}

sub filter_element_data {
    my ($self, %arg) = @_;

    # get HTML to be cleaned
    my $element = $arg{element};
    my ($param) = $self->param_names(element => $element);
    my $html = $arg{query}->param($param);

    return '' unless $html && length $html;

    debug(__PACKAGE__ . "->filter_element_data() - HTML coming from the browser: " . $html);

    # clean it
    $html = pkg('Markup::Gecko')->browser2db(
        html => pkg('Markup::IE')->browser2db(
            html => pkg('Markup::WebKit')->browser2db(html => $self->html_scrubber(html => $html))
        )
    );

    debug(__PACKAGE__ . "->filter_element_data() - Cleaned HTML: " . $html);

    # return the correct markup
    $html = pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->db2browser(html => $html);

    debug(__PACKAGE__ . "->filter_element_data() - HTML to the browser: " . $html);

    return $html;
}

#
# Called by Krang::Story::linked_stories() to build the asset list at publish time
#
sub linked_stories {
    my ($self, %arg) = @_;

    my ($element) = @arg{qw(element)};
    my $sep = $self->field_separator;
    $self->_do_linked_stories(%arg, html => [split(/$sep/, $element->data)]);
}

sub thaw_data {
    my ($self, %arg) = @_;
    my $sep = $self->field_separator;
    $arg{element}->data([split(/$sep/, $arg{data})]);
}

sub freeze_data {
    my ($self, %arg) = @_;
    my $sep = $self->field_separator;
    my $data = $arg{element}->data || [];
    return join($sep, @$data);
}

sub get_one_time_javascript {
    my ($self, %arg) = @_;

    my $field_sep = $self->field_separator;

    my $html = $self->poortext_init(%arg);

    $html .= <<END;
<script type="text/javascript">
//' keep emacs javascript-mode happy
Krang.ElementClass.PoorTextList = {
    clickHandler : function(event) {
        var target = Event.element(event);
        var item   = target.up();
        if (target.name) {
            var func = Krang.ElementClass.PoorTextList[target.name];
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

        var hidden      = currItem.up().next();
        var param       = hidden.id;
        var itemConfig  = Krang.ElementClass.PoorTextList[param];
        var id          = param + '_' + itemConfig.nextItemNumber++;

        var newPT = new Element('div', {id : id, className : itemConfig.className, style : itemConfig.style});
        var newItem = new Element('div', {className : id + ' poortextlist_item', style : itemConfig.itemStyle});
        newItem.appendChild(newPT);
        ['+', '\\u2212', '\\u2193', '\\u2191'].each(function(btn) {
                newItem.appendChild(new Element('input',
                     {type : 'button', value : btn, name : Krang.ElementClass.PoorTextList.functionFor[btn],
                      'class' : itemConfig.buttonClass}));


            });

        currItem.insert({after : newItem});

        // anyway show DELETE and DOWN button on current item
        currItem.down().next(1).show().next().show();

        if (Krang.ElementClass.PoorTextList.isLast(newItem)) {
            // hide DOWN button on new item
            newItem.down().next(2).hide();
        }

        // create new PoorText field
        var ptConfig = itemConfig.ptConfig;
        ptConfig["deferIframeCreation"] = false;
        var pt = new PoorText(newPT, ptConfig);
        pt.onFocus();
        setTimeout(function() {
            pt.focusEditNode();
        },10);

        // record this field
        PoorText.Krang.paramFor[id] = param;
    },

    item_delete : function(currItem) {
        var nextItem = currItem.next();
        var prevItem = currItem.previous();

        siblings = currItem.siblings();

        // make PT field inaccessible
        PoorText.id2obj[Krang.ElementClass.PoorTextList.get_pt_id(currItem)] = null;

        // remove it
        currItem.remove();

        if (siblings.length == 1) {
            siblings[0].down().next(1).hide().next().hide().next().hide();
            return currItem;
        }

        if (nextItem && Krang.ElementClass.PoorTextList.isFirst(nextItem)) {
            // show DOWN, hide UP button on future first item
            nextItem.down().next(2).show().next().hide();
        }

        if (prevItem && Krang.ElementClass.PoorTextList.isLast(prevItem)) {
            // hide DOWN, show UP button on future last item
            prevItem.down().next(2).hide().next().show();
        }

        return currItem;
    },

    item_down : function(currItem) {
        var nextItem = currItem.next();

        // store content
        var cpt = PoorText.id2obj[Krang.ElementClass.PoorTextList.get_pt_id(currItem)];
        var npt = PoorText.id2obj[Krang.ElementClass.PoorTextList.get_pt_id(nextItem)];
        cpt.storeForPostBack();
        npt.storeForPostBack();

        // swap content
        var tmp = cpt.getCurrHtml();
        cpt.setCurrHtml(npt.getCurrHtml());
        npt.setCurrHtml(tmp);
    },

    item_up : function(currItem) {
        var prevItem = currItem.previous();

        // store content
        var cpt = PoorText.id2obj[Krang.ElementClass.PoorTextList.get_pt_id(currItem)];
        var ppt = PoorText.id2obj[Krang.ElementClass.PoorTextList.get_pt_id(prevItem)];
        cpt.storeForPostBack();
        ppt.storeForPostBack();

        // swap content
        var tmp = cpt.getCurrHtml();
        cpt.setCurrHtml(ppt.getCurrHtml());
        ppt.setCurrHtml(tmp);
    },

    isFirst : function(item) {
        return ! item.previous();
    },

    isLast : function(item) {
        return ! item.next();
    },

    get_pt_id : function(item) {
        return item.readAttribute('class').replace('poortextlist_item', '').strip()
    },

    onSave : function(param) {

        var children = \$(param+'_container').childElements();

        var html = children.inject([], function(acc, item) {
           var pt = PoorText.id2obj[Krang.ElementClass.PoorTextList.get_pt_id(item)];
           if (pt) {
               var field = pt.returnHTML;
               if (field) { acc.push(field.value) }
           }
           return acc;
        });
        var returnElement = \$(param);
        returnElement.value = html.join("$field_sep");
    }
};
</script>
END

    return $html;
}

sub get_css_style {
    my ($self, %arg) = @_;
    my $element = $arg{element};

    my $w = $self->width;

    #
    # text flavour
    #
    return "width: ${w}px; float: left" if $self->type eq 'text';

    #
    # textarea flavour
    #
    #
    my $h = $self->height;

    return "width: ${w}px; height: ${h}px; float : left;";

}

sub command_spec {
    my ($self, %arg) = @_;

    # order matters!
    return {
        basic => [
            qw(bold    italic      underline
              cut      copy        paste
              add_html delete_html add_story_link
              redo     undo
              help     toggle_selectall)
        ],
        basic_with_special_chars => [
            qw(bold        italic      underline
              cut          copy        paste
              add_html     delete_html add_story_link
              redo         undo
              specialchars help        toggle_selectall)
        ],
        all => [
            qw(bold         italic       underline
              strikethrough subscript    superscript
              cut           copy         paste
              add_html      delete_html  add_story_link
              redo          undo
              specialchars  help         toggle_selectall)
        ],
    };
}

sub fill_template {
    my ($self, %arg) = @_;
    my ($element, $tmpl, $publisher) = @arg{qw(element tmpl publisher)};

    my $name      = $element->name;
    my $loop_name = $name . '_loop';
    my $item_name = $name . '_item';
    my @data      = @{$element->data || []};

    # get StoryLinks from publish context
    my %context = $publisher->publish_context();
    my $url_for = $context{poortext_story_links} || {};

    # replace Story IDs with URL
    $tmpl->param(
        $loop_name => [
            map {
                { $item_name => $self->replace_story_id_with_url(html => $_, url_for => $url_for) }
              } @data
        ]
    );
}

=head1 NAME

Krang::ElementClass::PoorTextList - a multi field WYSIWYG element

=head1 SYNOPSIS

   $class = pkg('ElementClass::PoorTextList')->new( 
        name     => "poortext",
        type     => 'textarea',
        commands => 'all',
   );

=head1 DESCRIPTION

This element combines the WYSIWYG capability of
L<Krang::ElementClass::PoorText> with the list management controls
of L<Krang::ElementClass::TextInputList>.  Where the latter comes with
HTML text input fields, this class comes with PoorText fields.

This class is based on L<Krang::ElementClass::_PoorTextBase>.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item type

May be 'text' or 'textarea' to mimic the two flavors of legacy text
input and textarea fields.

=item width

The width of the edit area. Defaults to 400px.

=item height

The height of the edit area. For type 'textarea' defaults to 120px.
For type 'text' this option takes no effect.

=item commands

This can be either a string denoting a pre-cooked set of WYSIWYG commands
or an array or command names. The pre-cooked sets are:

   basic                    => [ qw(bold     italic      underline
                                    cut      copy        paste
                                    add_html delete_html add_story_link
                                    redo     undo
                                    help     toggle_selectall)
                               ],
   basic_with_special_chars => [ qw(bold         italic      underline
                                    cut          copy        paste
                                    add_html     delete_html add_story_link
                                    redo         undo
                                    specialchars help        toggle_selectall)
                               ],
   all                      => [ qw(bold          italic       underline
                                    strikethrough subscript    superscript
                                    cut           copy         paste
                                    add_html      delete_html  add_story_link
                                    redo          undo
                                    specialchars  help         toggle_selectall) ],

Most of these commands should be self-evident. Some, however, are not:

=over

=item add_html

This command opens a popup allowing to wrap the selected text with a
A, ABBR or ACRONYM tag.

=item delete_html

Deletes an A, ABBR or ACRONYM around the current selection.

=item add_story_link

This command hooks Krang's StoryLink selection into PoorText fields.
The hard find feature known from L<Krang::ElementClass::StoryLink> is
also supported.

=item specialchars

This command displays a second toolbar allowing to insert double and
single curly quotes as well as the ndash.

=item toggle_selectall

This command is only accessible via the keyboard using the default
shortcut Ctrl-a.  PoorText implements this command as a toggle. When
deselecting, the original position of the cursor or the original
selection is restituted.

=back

=item command_button_bar

This boolean determines whether a button bar with the configured
commands will be displayed when the edit area receives focus.  (You
might want to just use the shortcuts. Which ones? Press Ctrl-h).  The
default is true.

=item special_char_bar

If true, the specialchar button bar will be displayed when the edit
area receives focus. In this case, even if the command button bar is
configured to contain the specialchars command (the omega sign), this
command will not be present. Defaults to false.

=item shortcut_for

This hashref maps commands and specialchars to shortcuts. The default
is:

    bold              => 'ctrl_b',
    italic            => 'ctrl_i',
    underline         => 'ctrl_u',
    subscript         => 'ctrl_d',
    superscript       => 'ctrl_s',
    strikethrough     => 'ctrl_t',
    toggle_selectall  => 'ctrl_a',
    add_html          => 'ctrl_l',
    delete_html       => 'ctrl_shift_l',
    add_story_link    => 'ctrt_shift_s',
    redo              => 'ctrl_y',
    undo              => 'ctrl_z',
    help              => 'ctrl_h',
    cut               => 'ctrl_x',
    copy              => 'ctrl_c',
    paste             => 'ctrl_v',
    specialchars      => 'ctrl_6',
    lsquo             => 'ctrl_4',
    rsquo             => 'ctrl_5',
    ldquo             => 'ctrl_2',
    rdquo             => 'ctrl_3',
    ndash             => 'ctrl_0',

(See F<htdocs/poortext/src/poortext_core.js> for more information)

=item defaults

Either a number specifying the number of input fields to be created
when creating the element, or an arrayref of strings that will
prepopulate the list of input fields. Defaults to 1.

=item find

The find parameter works the way known from
L<Krang::ElementClass::StoryLink>.

=back

=head2 Integrating PoorTextList with Xinha-based bulk editing

This elementclass may be used to represent (un)ordered HTML lists.
Legal values for the option C<bulk_edit_tag> are therefore limited to

  ul, ol

For

  p, h1, h2, h3, h4, h5, h6, address, pre

see L<Krang::ElementClass::PoorText>.

=head1 SEE ALSO

The base class L<Krang::ElementClass::_PoorTextBase> and the PoorText
source in F<htdocs/poortext/src/>.

=cut

1;
