package Krang::ElementClass::PoorText;
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

use Krang::ClassLoader MethodMaker => get_set => [qw( indent_size )];

sub new {
    my $pkg = shift;

    my %args_in       = @_;
    my %function_for  = ();
    my $bulk_edit_tag = $args_in{bulk_edit_tag};

    if ($bulk_edit_tag) {
        croak(__PACKAGE__ . "::new() - unsupported bulk_edit_tag value '$bulk_edit_tag'")
          unless $pkg->is_supported(tag => $bulk_edit_tag);

        $function_for{before_bulk_edit} = $args_in{before_bulk_edit}
          || sub {
            my %args = @_;
            return ${$args{element}->data}[0];
          };

        $function_for{before_bulk_save} = $args_in{before_bulk_save}
          || sub {
            my %args = @_;
            return [$args{data}, 0, 'left'];
          };
    }

    my %args = (
        width  => 380,
        height => 140,    # for 'textarea' flavour. For 'text' flavour see poortext.css '.pt-text'
        command_button_bar => 1,
        special_char_bar   => 0,
        commands           => 'all_xinha',
        indent_size        => 20,
        @_,
        %function_for,
    );

    # validate commands spec
    my $command_spec = $pkg->command_spec();
    if ($args{commands}) {
        if (ref($args{commands})) {
            croak(  __PACKAGE__
                  . "::new() - 'commands' option must be string or arrayref, but is "
                  . ref($args{commands}))
              if ref($args{commands}) ne 'ARRAY';
        } elsif (!exists $command_spec->{$args{commands}}) {
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

    debug(__PACKAGE__ . "->load_query_data($param) - HTML coming from the browser: " . $html);

    # fix the markup
    if ($html) {
        $html = pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->browser2db(html => $html);

        debug(__PACKAGE__ . "->load_query_data($param) - HTML sent to DB: " . $html);
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
    my $text   = $data->[0] || '';
    my $indent = $data->[1] || 0;
    my $align  = $data->[2] || 'left';

    # get some setup stuff
    my $config = $self->get_pt_config(%arg, has_content => $text);
    my $class  = $self->get_css_class(%arg);
    my $style  = $self->get_css_style(%arg, indent => $indent, align => $align);

    # JavaScript init code: add only once
    my @sibs = grep { $_->class->isa(__PACKAGE__) } $element->parent()->children();
    if ($sibs[0]->xpath() eq $element->xpath()) {

        # I''m the first!  Insert one-time JavaScript
        $html .= $self->poortext_init(%arg);
    }

    # configure the element
    my $id = md5_hex($param);
    $html .= <<END;
<script type="text/javascript">
    // configure this element
    Krang.PoorTextCreationArguments.push(["$id", "$param", $config]);
</script>
END

    # create the edit area DIV and ...
    $text = pkg("Markup::$ENV{KRANG_BROWSER_ENGINE}")->db2browser(html => $text);
    $html .= qq{<div class="$class" style="$style" id="$id">} . $text . qq{</div>\n};

    # ... its hidden input field used to return the text
    # !! escape single quotes and enclose $text in single quotes !!
    $text =~ s/'/&#39;/g;
    $html .= qq[<input type="hidden" name="$param" value='$text' id="${id}_return"/>];

    debug(__PACKAGE__ . "->input_form($param) - HTML sent to the browser: " . $text);

    # the hidden field for text indent
    $html .= qq[<input type="hidden" name="${param}_indent" value="$indent" id="${id}_indent"/>];

    # the hidden field for text alignment
    $html .= qq[<input type="hidden" name="${param}_align" value="$align" id="${id}_align"/>];

    # Add hard find parameters
    my $find = encode_base64(nfreeze(scalar($self->find())));
    $html .= $query->hidden("hard_find_$param", $find);

    return $html;
}

# we override this method so that it won't escape the HTML
sub view_data {
    my ($self,    %arg)  = @_;
    my ($element, $data) = @arg{qw(element data)};

    return '' unless $data->[0];

    return <<END;
<div style="border-bottom: 1px solid #99999">
    Indent: $data->[1]px &mdash; Text Alignment: $data->[2]
</div>
$data->[0]
END
}

#
# Called by pkg('Story)->linked_stories() to build the asset list at publish time
#
sub linked_stories {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};

    my $data = $element->data;
    $self->_do_linked_stories(%arg, html => [$data->[0]]);
}

sub template_data {
    my ($self, %arg) = @_;

    my ($element, $publisher) = @arg{qw(element publisher)};

    # get StoryLinks from publish context
    my %context = $publisher->publish_context();
    my $url_for = $context{poortext_story_links} || {};

    # get the element's HTML
    my $data = $element->data;

    # replace Story IDs with their URL
    my $html = $self->replace_story_id_with_url(html => $data->[0], url_for => $url_for);

    # return it
    return <<END;
<div style="padding-left: $data->[1]; padding-right: $data->[1]; text-align: $data->[2]">
  $html
</div>
END
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

        # HTML INDENT  ALIGN
        return $element->data(['', 0, 'left']);
    }
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

sub command_spec {
    my ($self, %arg) = @_;

    # order matters!
    return {
        basic => [
            qw(bold     italic      underline
              cut      copy        paste
              add_html delete_html add_story_link
              redo     undo
              help     toggle_selectall)
        ],
        basic_with_special_chars => [
            qw(bold         italic      underline
              cut          copy        paste
              add_html     delete_html add_story_link
              redo         undo
              specialchars help        toggle_selectall)
        ],
        all_xinha => [
            qw(bold          italic       underline
              strikethrough subscript    superscript
              cut           copy         paste
              add_html      delete_html  add_story_link
              redo          undo
              specialchars  help         toggle_selectall)
        ],
        all => [
            qw(bold          italic       underline
              strikethrough subscript    superscript
              cut           copy         paste
              align_left    align_center align_right justify
              indent        outdent
              add_html      delete_html  add_story_link
              redo          undo
              specialchars  help         toggle_selectall)
        ],
    };
}

sub is_supported {
    my ($self, %arg) = @_;

    my %supported = (
        p       => 1,
        pre     => 1,
        h1      => 1,
        h2      => 1,
        h3      => 1,
        h4      => 1,
        h5      => 1,
        h6      => 1,
        address => 1,
    );

    return $supported{$arg{tag}};
}

=head1 NAME

Krang::ElementClass::PoorText - WYSIWYG element

=head1 SYNOPSIS

   $class = pkg('ElementClass::PoorText')->new(
        name          => "paragraph",
        type          => 'textarea',
        commands      => 'all_xinha',
        bulk_edit_tag => 'p',
   );

=head1 DESCRIPTION

This element provides a WYSIWYG text editor for HTML by integrating
with the PoorText WYSIWYG element. It is based on
L<Krang::ElementClass::_PoorTextBase>.

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
   all_xinha                => [ qw(bold          italic       underline
                                    strikethrough subscript    superscript
                                    cut           copy         paste
                                    add_html      delete_html  add_story_link
                                    redo          undo
                                    specialchars  help         toggle_selectall)
                               ],
   all                      => [ qw(bold          italic       underline
                                    strikethrough subscript    superscript
                                    cut           copy         paste
                                    align_left    align_center align_right justify
                                    indent        outdent
                                    add_html      delete_html  add_story_link
                                    redo          undo
                                    specialchars  help         toggle_selectall) ],

Most of these commands should be self-evident. Some, however, are not:

Note the difference between C<all_xinha> and C<all>. The former
includes all commands supported when integrating PoorText with
Xinha-based bulk editing, excluding the C<align> and C<indent/outdent>
commands which are part of C<all>.

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
    add_story_link    => 'ctrl_shift_s',
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


(See F<htdocs/poortext/src/poortext_core.js> for more information)

=item indent_size

If the commands 'indent' and 'outdent' are configured, this option
specifies the number of pixels to indent and outdent. Defaults to 20.

=item find

The find parameter works the way known from
L<Krang::ElementClass::StoryLink>.

=back

=head2 Integrating PoorText with Xinha-based bulk editing

As a PoorText field may contain HTML inline-level tags only, the set
of values allowed for the option C<bulk_edit_tag> is limited to:

  p, h1, h2, h3, h4, h5, h6, address, pre

(Un)ordered lists and tables are not allowed. For (un)ordered lists
see L<Krang::ElementClass::PoorTextList>.

=head1 SEE ALSO

The base class L<Krang::ElementClass::_PoorTextBase> and the PoorText
source in F<htdocs/poortext/src/>.

=cut

1;
