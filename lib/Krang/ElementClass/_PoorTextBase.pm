package Krang::ElementClass::_PoorTextBase;
use strict;
use warnings;

use Krang::ClassFactory qw(pkg);

use Krang::ClassLoader base => 'ElementClass';

use Krang::ClassLoader 'Info';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'URL';
use Krang::ClassLoader 'Markup::Gecko';
use Krang::ClassLoader 'Markup::IE';
use Krang::ClassLoader 'Markup::WebKit';
use Krang::ClassLoader Localization => qw(localize);
use Krang::ClassLoader Log          => qw(debug);
use Krang::ClassLoader Conf         => qw(BrowserSpeedBoost);


use HTML::Scrubber;
use Digest::MD5 qw(md5_hex);
use JSON::Any;
use Carp qw(croak);

# For *Link hard find feature
use Storable qw(nfreeze);
use MIME::Base64 qw(encode_base64);

use Krang::MethodMaker get_set => [
    qw(
      type   commands
      width  special_char_bar
      height command_button_bar shortcut_for
      )
  ],
  hash => [qw(find)];


our %js_name_for = (
    type               => 'type',
    commands           => 'availableCommands',
    special_char_bar   => 'attachSpecialCharBar',
    command_button_bar => 'attachButtonBar',
    shortcut_for       => 'shortcutFor',
    indent_size        => 'indentSize',
);

=head1 NAME

Krang::ElementClass::PoorText - Base class for PoorText element classes

=head1 SYNOPSIS

None.

=head1 DESCRIPTION

This module inherits from L<Krang::ElementClass> and provides the base
class for PoorText elementclasses like L<Krang::ElementClass::PoorText>.

=head1 INTERFACE

=head1 OBJECT ATTRIBUTES

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item type

May be 'text' or 'textarea' to mimic the two flavors of HTML text
input and textarea fields.

=item width

The width of the edit area. Defaults to 400px.

=item height

The height of the edit area. For type 'textarea' defaults to 120px.
For type 'text' this option takes no effect.

=item commands

This can be either a string denoting a pre-cooked set of WYSIWYG
commands or an array or command names. The pre-cooked sets must be
defined by concrete element classes inheriting from this base
class. See also B<command_spec()>.  Available commands are:

   bold          italic       underline
   strikethrough subscript    superscript
   cut           copy         paste
   align_left    align_center align_right justify
   indent        outdent
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

=back

=head2 METHODS

=over

=item C<< $pkg->poortext_init() >>

This method returns as a string the one time JavaScript initializing
PoorText fields.  The Javascript pulls in the browser-specific
PoorText JavaScript file, installs a mouse down handler to enable story
previewing on StoryLinks inserted in PoorText fields and initializes
those fields.

=cut

sub poortext_init {
    my ($self, %arg) = @_;

    my $install_id = pkg('Info')->install_id();
    my $static_url = BrowserSpeedBoost ? "/static/$install_id" : '';
    my $lang       = localize('en');
    $lang          = substr($lang, 0, 2) unless $lang eq 'en';

    my $html = <<END;
<script type="text/javascript">
    // pull in the JavaScript
if (!Krang.PoorTextLoaded) {
    // pull in a browser-engine-specific version of PoorText's JavaScript
    var pt_script = new Element(
       'script',
       { type: "text/javascript",
         src: "$static_url/poortext/poortext_$ENV{KRANG_BROWSER_ENGINE}.js"}
    );
    document.body.appendChild(pt_script);

    // I tried the same appending procedure for the CSS file poortext/css/poortext.css,
    // but for WebKit that comes to late, so I included it in templates/header.base.tmpl

    // make sure we do this only once
    Krang.PoorTextLoaded = true;
}

// init function
poortext_init = function() {
    if (Krang.PoorTextInitialized) { return }

    // is poortext_<BROWSER_ENGINE>.js loaded ?
    if (typeof PoorText == 'undefined') {
        setTimeout(poortext_init, 10);
        return;
    }

    Krang.PoorTextInitialized = true;

    // deactivate the autoload handler
    PoorText.autoload = false;

    // language is a global config
    PoorText.config = {
        lang              : "$lang",
        useMarkupFilters  : false
    };

    // make them all fields
    Krang.PoorTextCreationArguments.each(function(pts) {
        var pt_id  = pts[0];
        var param  = pts[1];
        var config = pts[2];

        // map PoorText field id to Krang element param
        PoorText.Krang.paramFor[pt_id] = param;

        // make PoorText fields
        pt = new PoorText(pt_id, config);

        // add a preview handler for links and StoryLinks
        // IE does dispatch no 'click' event on contenteditable elements
        // so we use mousedown
        pt.onEditNodeReady(function() {
            this.observe('mousedown', 'krang_preview', function(e) {
                if (e.target.nodeName.toLowerCase() != 'a') { return }
                if (e.ctrlKey
                    || (Prototype.Browser.IE && e.button == 4)
                    || (!Prototype.Browser.IE && e.button == 1))
                    {
                        var elm = e.target;
                        if (elm.getAttribute('_poortext_tag') == 'a') {
                            var storyID = elm.getAttribute('_story_id');
                            if (storyID) {
                                // StoryLink
                                Krang.preview('story', storyID);
                                Event.stop(e);
                            } else {
                                // other links
                                var instance = Krang.instance;
                                instance = instance.toLowerCase().replace(/[^a-z]/g, '' );
                                window.open(elm.getAttribute('href'), instance);
                            }
                        }
                    }
            }, false);
        }.bind(pt));
    });

    // finish with some global stuff
    PoorText.finish_init();
}

// call init function
Krang.onload(function() {
    poortext_init();
});
END

        $html .= <<'END';
// save away the last focused PoorText field to avoid race conditions
// and hide our popups
Krang.ElementEditor.add_save_hook(function() {
    Krang.PoorTextInitialized = false;
    Krang.PoorTextCreationArguments = [];
    var pt = PoorText.focusedObj;
    if (pt) {
        pt.storeForPostBack();
        if ($('pt-btnBar')) $('pt-btnBar').hide();
        if ($('pt-specialCharBar')) $('pt-specialCharBar').hide();
        if ($('pt-popup-addHTML')) $('pt-popup-addHTML').hide();
    }
});
</script>
END

    return $html;
}

=item C<< $pkg->get_css_class() >>

This method returns a string consisting of CSS class names used to
style PoorText fields depending on their flavor.

=cut

sub get_css_class {
    my ($self, %arg) = @_;

    # CSS class property
    return $self->type eq 'text'
      ? "poortext pt-text"
      : "poortext";
}

=item C<< $pkg->get_pt_config(has_content => $text) >>

This method takes a concret PoorText elementclass configuration and
transforms it into a string representing a JavaScript object litteral
used to configure PoorText elements.

=cut

sub get_pt_config {
    my ($self, %arg) = @_;
    my @conf   = ();

    # $conf will be part of a JavaScript object litteral
    for my $c (qw(
                     type
                     special_char_bar
                     command_button_bar  indent_size
                )) {
        my $conf;
        if ($conf = $self->can($c) ? $self->$c : 0) {
            if (ref($conf)) {
                push @conf, "$js_name_for{$c} : " . JSON::Any->objToJson($conf);
            } else {
                $conf = '' unless $conf;    # make sure '0' evalutes to false in JS
                if ($conf =~ /^\d+$/) {
                    push @conf, qq[$js_name_for{$c} : $conf];
                } else {
                    push @conf, qq[$js_name_for{$c} : "$conf"];
                }
            }
        }
    }

    # add the commands spec
    my $cmd = $self->get_command_spec(%arg);
    push @conf, $cmd if $cmd;

    # add shortcuts spec
    my $shortcuts = $self->get_shortcut_spec(%arg);
    push @conf, $shortcuts if $shortcuts;

    # add CSS files in IFrame HEAD element
    push @conf, qq{iframeHead : '<link rel="stylesheet" type="text/css" href="/poortext/css/poortext.css">'};

    # if there's no text yet, we assume it's a newly added field,
    # hence we don't defer creating the IFrame (in browsers that
    # require it)
    my $defer = $arg{has_content} ? 'true' : 'false';
    push @conf, "deferIframeCreation: $defer";

    # stringify
    my $conf = join(',', @conf);

    return "{$conf}";
}

=item C<< $pkg->get_command_spec(%arg) >>

This method is responsible for turning the "commands" configuration of
PoorText fields into a string suitable to be integrated in inline
JavaScript.

=cut

sub get_command_spec {
    my ($self, %arg) = @_;

    my $spec = $self->commands || 'all';

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
    croak __PACKAGE__ . "->get_command_spec() : Unknow value for key 'commands' => $spec";
}

=item C<< $pkg->command_spec() >>

This method return a hashref mapping names of pre-cooked command sets
to arrayrefs holding command names for PoorText elements. It must be
implemented by child classes.

B<Example>

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
        all => [
            qw(bold         italic       underline
              strikethrough subscript    superscript
              cut           copy         paste
              align_left    align_center align_right justify
              indent        outdent
              add_html      delete_html  add_story_link
              redo          undo
              specialchars  help         toggle_selectall)
        ],
    };

=cut

sub command_spec {
    my ($self, %arg) = @_;

    croak "command_spec() must be defined in child class '" . ref($self) . "'";
}


=item C<< $pkg->get_shortcut_spec(%arg) >>

This method is responsible for turning the "shortcut_for" configuration
into a string suitable to be integrated in inline JavaScript.

=cut

sub get_shortcut_spec {
    my ($self, %arg) = @_;

    my $spec = $self->shortcut_for;

    if ($spec) {
        return 'shortcutFor: ' . JSON::Any->objToJson($spec);
    } else {
        return 'shortcutFor: '
          . JSON::Any->objToJson(
            {
                bold             => 'ctrl_b',
                italic           => 'ctrl_i',
                underline        => 'ctrl_u',
                subscript        => 'ctrl_d',
                superscript      => 'ctrl_s',
                strikethrough    => 'ctrl_t',
                toggle_selectall => 'ctrl_a',
                add_html         => 'ctrl_l',
                delete_html      => 'ctrl_shift_l',
                add_story_link   => 'ctrl_shift_s',
                redo             => 'ctrl_y',
                undo             => 'ctrl_z',
                help             => 'ctrl_h',
                cut              => 'ctrl_x',
                copy             => 'ctrl_c',
                paste            => 'ctrl_v',
                specialchars     => 'ctrl_6',
                align_left       => 'ctrl_q',
                align_center     => 'ctrl_e',
                align_right      => 'ctrl_r',
                justify          => 'ctrl_w',
                indent           => 'tab',
                outdent          => 'shift_tab',
                lsquo            => 'ctrl_4',
                rsquo            => 'ctrl_5',
                ldquo            => 'ctrl_2',
                rdquo            => 'ctrl_3',
                ndash            => 'ctrl_0',
            }
          );
    }
}

=item C<< $pkg->html_scrubber(html => $html) >>

This method returns the scrubbed $html.  It uses HTML::Scrubber
internally.

=cut

sub html_scrubber {
    my ($self, %arg) = @_;

    my @block_elements  = (qw());
    my @inline_elements = $self->type eq 'text'
      ? (qw(a b del em i span strong strike u sub sup))
      : (qw(a b del em i span strong strike u sub sup br));

    my $scrubber = HTML::Scrubber->new(

        # deny all tags and all attribs
        default => [0, {'*' => 0}],

        # however allow some tags
        allow => [@block_elements, @inline_elements],

        # and allow some attribs with A tags
        rules => [
            a => {
                '*'           => 0,    # deny all attribs on A tags
                href          => 1,    # allow some attribs
                title         => 1,
                class         => 1,
                _poortext_tag => 1,
                _poortext_url => 1,
                _story_id     => 1,
            },
            span => {
                '*'   => 0,
                style => 1,
            },
        ],
    );

    return $scrubber->scrub($arg{html});
}

=item C<< $pkg->filter_element_data(%arg) >>

This method is called by L<Krang::CGI::ElementEditor>'s ajaxy runmode
'filter_element_data' to scrub the HTML pasted into PoorText
fields. It also takes care to convert pasted markup into tags
understood by the WYSIWYG commands of the current browser.  This
runmode is called whenever the user triggers a paste action.

=cut

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

=item C<< $pkg->_do_linked_stories(%arg) >>

This method is the workhorse of 'linked_stories()', a method that must
be implemented by child classes to make the linked-stories-mechanism
work with StoryLinks inserted in PoorText fields.  Moreover, this
method stores a StoryID -> StoryURL map in the publish context under
the key 'poortext_story_links'.  Publish code may use this map to
replace the IDs with URLs.

=cut

sub _do_linked_stories {
    my ($self, %arg) = @_;

    my ($element, $publisher, $story_links, $html) = @arg{qw(element publisher story_links html)};

    # pass them to template_data() via publish context
    my %context = $publisher->publish_context();
    my $url_for = $context{poortext_story_links} || {};

    for my $hunk (@$html) {

        # get story link IDs out of '_story_id' attrib
        while ($hunk =~ /_story_id="(\d+)"/g) {
            my $story;
            my $id = $1;

            if ($id && (($story) = pkg('Story')->find(story_id => $id))) {

                # for asset list building: fill story_links hashref
                $story_links->{$id} = $story;

                # for template_data(): use the current URL of the linked story ID
                $url_for->{$id} = pkg('URL')->real_url(
                    object    => $story,
                    publisher => $publisher
                );
            }
        }
    }

    # remember us
    $publisher->publish_context(poortext_story_links => $url_for);
}

=item C<< $pkg->replace_story_id_with_url(%arg) >>

This method must be called by publish code to transform StoryLinks
into real HTML links.

=cut

sub replace_story_id_with_url {
    my ($self, %arg) = @_;

    my ($html, $url_for) = @arg{ qw(html url_for) };

    if (%$url_for) {

        # fix the StoryLinks' HREF according to current URL
        1 while $html =~ s/_story_id="(\d+)" [^>]+ href="[^"]+"
                          /'href="' . $url_for->{$1} . '"'
                          /exg;
    }

    # finally chop CSS class from links
    $html =~ s/_poortext_tag="[^"]*"//;
    $html =~ s/_poortext_url="[^"]*"//;
    $html =~ s/_story_id="[^"]*"//;
    $html =~ s/class="[^"]*"//;

    return $html;
}

=item C<< $pkg->field_separator() >>

This method returns a field separator for multi-field elements.  It's
the first character of Unicode's first PUA (privat use area).

=cut

sub field_separator { return "\x{E000}" }

=back

=cut

1;
