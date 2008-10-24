package Krang::ElementClass::PoorText;
use strict;
use warnings;

use Krang::ClassFactory qw(pkg);

use Krang::ClassLoader base => 'ElementClass';

use Krang::ClassLoader Log          => qw(critical);
use Krang::ClassLoader Message      => qw(add_message);
use Krang::ClassLoader Localization => qw(localize);
use Krang::ClassLoader 'Markup::Gecko';
use Krang::ClassLoader 'Markup::IE';
use Krang::ClassLoader 'Markup::WebKit';

use Digest::MD5 qw(md5_hex);
use JSON::Any;
use Carp qw(croak);

use Krang::MethodMaker get_set => [
    qw(
      type   commands
      width  special_char_bar   shortcut_for
      height command_button_bar indent_size
      )
];

our %js_name_for = (
    type               => 'type',
    commands           => 'availableCommands',
    special_char_bar   => 'attachSpecialCharBar',
    command_button_bar => 'attachButtonBar',
    shortcut_for       => 'shortcutFor',
    indent_size        => 'indentSize',
);

sub new {
    my $pkg  = shift;
    my %args = (
        width  => 400,
        height => 120,    # for 'textarea' flavour. For 'text' flavour see poortext.css '.pt-text'
        command_button_bar => 1,
        special_char_bar   => 0,
        @_
    );

    # validate commands spec
    my $command_spec = $pkg->command_spec();
    if ($args{commands}) {
        if (!exists $command_spec->{$args{commands}}) {
            croak("\"$args{commands}\" is not a known set of commands");
        }
    }

    return $pkg->SUPER::new(%args);
}

sub mark_form_invalid {
    my ($self, %arg) = @_;
    my ($html) = @arg{qw(html)};
    return qq{<div style="border-left: 3px solid #ffffac">$html</div>};
}
sub validate { 1 }

sub load_query_data {
    my ($self,  %args)    = @_;
    my ($query, $element) = @args{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    # the HTML
    my $html = $query->param($param);

    critical(__PACKAGE__ . "->load_query_data($param) - HTML coming from the browser: " . $html);

    # fix the markup
    if ($html) {
        $html = pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->browser2db(html => $html);

        critical(__PACKAGE__ . "->load_query_data($param) - HTML sent to DB: " . $html);
    }

    # the INDENT and ALIGN
    my $indent = $query->param("${param}_indent");
    my $align  = $query->param("${param}_align");

    $element->data([$html, $indent, $align]);
}

sub input_form {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);

    # the returned HTML
    my $html = "";

    # data has multiple fields: HTML INDENT ALIGN
    my $data   = $element->data;
    my $text   = $data->[0] || $query->param($param) || '';
    my $indent = $data->[1] || $query->param("${param}_indent") || 0;
    my $align  = $data->[2] || $query->param("${param}_align") || 'left';

    # get some setup stuff
    my $lang = localize('en');
    $lang = substr($lang, 0, 2) unless $lang eq 'en';
    my $install_id = pkg('Info')->install_id();
    my $config     = $self->get_pt_config(%arg);
    my $class      = $self->get_css_class(%arg);
    my $style      = $self->get_css_style(%arg, indent => $indent, align => $align);

    # JavaScript init code: add only once
    my @sibs = grep { $_->class->isa(__PACKAGE__) } $element->parent()->children();
    if ($sibs[0]->xpath() eq $element->xpath()) {

        # I''m the first!  Insert one-time JavaScript
        $html .= <<END;
<script type="text/javascript">
    // pull in the JavaScript
if (!Krang.PoorTextLoaded) {
    // the core poortext.js which will also pull in a browser-specific JavaScript
    var pt_script = new Element(
       'script',
       { type: "text/javascript",
         src: "/static/$install_id/poortext/poortext_$ENV{KRANG_BROWSER_ENGINE}.js"}
    );
    document.body.appendChild(pt_script);

    // I tried the same appending procedure for the CSS file poortext/poortext.css,
    // but for WebKit that comes to late, so I included it in templates/header.base.tmpl

    // make sure we do this only once
    Krang.PoorTextLoaded = true;
}

// init function
poortext_elements = new Array();
poortext_init = function() {
    // is poortext.js loaded ?
    if (typeof PoorText == 'undefined') {
        setTimeout(poortext_init, 10);
        return;
    }

    // deactivate the autoload handler
    PoorText.autoload = false;

    // is poortext_<browser-specific>.js loaded ?
    if (typeof PoorText.prototype.makeEditable == 'undefined') {
        setTimeout(poortext_init, 10);
        return;
    }

    // language is a global config
    PoorText.config = { lang : "$lang" };

    // make them all fields
    poortext_elements.each(function(pt) {
        new PoorText(pt[0], pt[1]);
    });

    // finish with some global stuff
    PoorText.finish_init();
}

// call init function
Krang.onload(function() {
    poortext_init();
});

// save away the last focused PoorText field to avoid race conditions
Krang.ElementEditor.add_save_hook(function() {
    var pt = PoorText.focusedObj;
    if (pt) {
        pt.storeForPostBack();
    }
});
</script>
END
    }

    # configure the element
    my $id = md5_hex($param);
    $html .= <<END;
<script type="text/javascript">
    // configure this element
    var config = {
        iframeHead : '<link rel="stylesheet" type="text/css" href="/poortext/poortext.css">'
        $config
    };
    poortext_elements.push(["$id", config]);
</script>
END

    # create the edit area DIV and ...
    $text = pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->db2browser(html => $text);
    $html .= qq{<div class="$class" style="$style" id="$id">} . $text . qq{</div>\n};

    # ... its hidden input field used to return the text
    $html .= qq[<input type="hidden" name="$param" value='$text' id="${id}_return"/>];

    critical(__PACKAGE__ . "->input_form($param) - HTML sent to the browser: " . $text);

    # the hidden field for text indent
    $html .= qq[<input type="hidden" name="${param}_indent" value="$indent" id="${id}_indent"/>];

    # the hidden field for text alignment
    $html .= qq[<input type="hidden" name="${param}_align" value="$align" id="${id}_align"/>];

    return $html;
}

# we override this method so that it won't escape the HTML
sub view_data {
    my ($self,    %arg)  = @_;
    my ($element, $data) = @arg{qw(element data)};

    return '' unless $data->[0];

    return $data->[0] if $element->class->type eq 'text';

    return <<END;
<div style="border-bottom: 1px solid #99999">
    Indent: $data->[1]px &mdash; Text Alignment: $data->[2]
</div>
$data->[0]
END
}

sub template_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};

    my $data = $element->data;

    return $data->[0] if $element->class->type eq 'text';

    return <<END;
<div style="padding-left: $data->[1]; padding-right: $data->[1]; text-align: $data->[2]">
  $data->[0]
</div>
END
}

sub freeze_data {
    my ($self, %arg) = @_;
    my $element = $arg{element};
    my $data    = $element->data || [];
    my $sep     = $self->get_separator();
    return join($sep, @$data);
}

sub thaw_data {
    my ($self,    %arg)  = @_;
    my ($element, $data) = @arg{qw(element data)};

    if ($data) {
        my $sep = $self->get_separator();
        return $element->data([split(/\Q$sep/, $data)]);
    } else {

        # HTML INDENT  ALIGN
        return $element->data(['', 0, 'left']);
    }
}

sub get_pt_config {
    my ($self,  %arg)     = @_;
    my ($query, $element) = @arg{qw(query element)};

    my $class = $element->class;
    my @conf  = ();

    # $conf will be part of a JavaScript object litteral
    for my $c (
        qw(
        type
        special_char_bar    shortcut_for
        command_button_bar  indent_size
        )
      )
    {

        my $conf;
        if ($conf = $class->$c) {
            if (ref($conf)) {
                push @conf, "$js_name_for{$c} : " . JSON::Any->objToJson($conf);
            } else {
                $conf = '' unless $conf;    # make sure '0' evalutes to false in JS
                push @conf, "$js_name_for{$c} : \"$conf\"";
            }
        }
    }

    # add the commands spec
    my $cmd = $self->get_command_spec(%arg);
    push @conf, $cmd if $cmd;

    # stringify
    my $conf = join(',', @conf);

    # prepend a comma since its gonna be part of a JS object
    return $conf ? ",\n$conf" : '';
}

sub get_css_class {
    my ($self, %arg) = @_;

    # CSS class property
    return $arg{element}->class->type eq 'text'
      ? "poortext pt-text"
      : "poortext";
}

sub get_css_style {
    my ($self, %arg) = @_;
    my $element = $arg{element};

    my $w = $element->class->width;

    #
    # text flavour
    #
    return "width: ${w}px;" if $element->class->type eq 'text';

    #
    # textarea flavour
    #
    #
    my $h = $element->class->height;

    # width and indent (padding)
    my $indent = $arg{indent};
    $w -= ($indent * 2);

    return
      "width: ${w}px; height: ${h}px; padding-left: ${indent}px; padding-right: ${indent}px; text-align: $arg{align};";

}

sub get_command_spec {
    my ($self, %arg) = @_;

    my $spec = $arg{element}->class->commands;

    # use the default coming with poortext.js
    return unless $spec;

    # custom command spec
    if (ref($spec) eq 'ARRAY') {
        return 'availableCommands: ' . JSON::Any->objToJson($spec);
    }

    # cooked spec
    my $command_spec = $self->command_spec();

    for my $cooked (keys %$command_spec) {
        if ($spec eq $cooked) {
            return 'availableCommands: ' . JSON::Any->objToJson($command_spec->{$cooked});
        }
    }

    # unknown command spec
    croak __PACKAGE__ . "->get_command_spec() : Unknow value for key 'commands' -> [ $spec ]";
}

sub command_spec {
    my ($self, %arg) = @_;

    # order matters!
    return {
        basic => [
            qw(bold     italic      underline
              cut      copy        paste
              add_html delete_html
              redo     undo
              help)
        ],
        basic_with_special_chars => [
            qw(bold         italic      underline
              cut          copy        paste
              add_html     delete_html
              redo         undo
              specialchars help)
        ],
        all => [
            qw(bold          italic       underline
              strikethrough subscript    superscript
              cut           copy         paste
              align_left    align_center align_right justify
              indent        outdent
              add_html      delete_html
              redo          undo
              specialchars  help)
        ],
    };
}

sub get_separator { return "\x{E000}" }

=head1 NAME

Krang::ElementClass::PoorText - WYSIWYG element

=head1 SYNOPSIS

   $class = pkg('ElementClass::PoorText')->new(
        name     => "poortext",
        type     => 'textarea',
        commands => 'all',
   );

=head1 DESCRIPTION

This element provides a WYSIWYG text editor for HTML by integrating
with the PoorText WYSIWYG element

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
                                    add_html delete_html
                                    redo     undo
                                    help)
                               ],
   basic_with_special_chars => [ qw(bold         italic      underline
                                    cut          copy        paste
                                    add_html     delete_html
                                    redo         undo
                                    specialchars help)
                               ],
   all                      => [ qw(bold          italic       underline
                                    strikethrough subscript    superscript
                                    cut           copy         paste
                                    align_left    align_center align_right justify
                                    indent        outdent
                                    add_html      delete_html
                                    redo          undo
                                    specialchars  help) ],

Most of these commands should be self-evident. Some, however, are not:

=over

=item add_html

This command opens a popup allowing to wrap the selected text with a
A, ABBR or ACRONYM tag.

=item delete_html

Deletes an A, ABBR or ACRONYM around the current selection.

=item specialchars

This command displays a second toolbar allowing to insert double and
single curly quotes as well as the ndash.

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
    redo              => 'ctrl_y',
    undo              => 'ctrl_z',
    help              => 'ctrl_h',
    cut               => 'ctrl_x',
    copy              => 'ctrl_c',
    paste             => 'ctrl_v',
    specialchars      => 'ctrl_6',
    align_left        => 'ctrl_q',
    align_center      => 'ctrl_e',
    align_right       => 'ctrl_r',
    justify           => 'ctrl_w',
    indent            => 'tab',
    outdent           => 'shift_tab',
    lsquo             => 'ctrl_4',
    rsquo             => 'ctrl_5',
    ldquo             => 'ctrl_2',
    rdquo             => 'ctrl_3',
    ndash             => 'ctrl_0',

(See F<htdocs/poortext/poortext_core.js> for more information)

=item indent_size

If the commands 'indent' and 'outdent' are configured, this option
specifies the number of pixels to indent and outdent. Defaults to 20.

=back

=head1 SEE ALSO

The PoorText source in F<htdocs/poortext/>.

=cut

1;
