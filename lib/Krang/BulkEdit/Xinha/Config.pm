package Krang::BulkEdit::Xinha::Config;
use warnings;
use strict;

use Krang::Log qw(critical);

use Krang::ClassLoader MethodMaker => new => 'new';

use HTML::Scrubber;

=head1 NAME

Krang::BulkEdit::Xinha::Config - Class to configure Xinha-based bulk editing

=head1 SYNOPSIS

Krang::BulkEdit::Xinha::Config - Class to configure for Xinha-based bulk editing

=head1 DESCRIPTION

This module represents the default configuration of Xinha-based bulk
editing as implemented in pkg('BulkEdit::Xinha').

You may modify this configuration by subclassing this module.

=head1 INTERFACE

=over

=item pkg('BulkEdit::Xinha::Config')->toolbar(formatblock => $boolean)

Returns a string representing a JavaScript array passed to
F<templates/ElementEditor/edit.base.tmpl> to configure Xinha's
toolbar.

The default configuration is

      [
        "bold", "italic", "underline", "separator",
        "insertorderedlist", "insertunorderedlist", "separator",
        "inserthorizontalrule", "createlink", "separator",
        "subscript", "superscript", "separator",
        "copy", "cut", "paste", "separator",
        "htmlmode", "separator",
        "undo", "redo"
      ]

If 'formatblock' is true

        "formatblock", "space",

will be prepended.

=cut

sub xinha_toolbar {
    my ($self, %arg) = @_;

    my @formatblock = qw(
      bold                 italic              underline separator
      insertorderedlist    insertunorderedlist separator
      inserthorizontalrule createlink          separator
      subscript            superscript         separator
      copy                 cut                 paste     separator
      htmlmode             separator
      undo                 redo
    );

    if ($arg{include_formatblock}) {
        unshift @formatblock, qw( formatblock space );
    }

    return JSON::Any->objToJson(\@formatblock);
}

=item pkg('BulkEdit::Xinha::Config')->html_scrubber(html => $html);

This method calls upon HTML::Scrubber to scrub and sanitize the HTML
coming from Xinha bulk edit, according to a white-listing approach.

The B<default> is to disallow all HTMLElements and to disallow all
attributes of allowed HTMLElements (no typo!).

Some HTMLElements are allowed:

The B<allow> list contains:

   @block_elements  = ( qw(p h1 h2 h3 h4 h5 h6 ol ul hr li)   );

and

   @inline_elements = ( qw(a br em strong strike u sub sup) );

Attributes of these allowed elements are stripped out because of the
default rule to disallow all attributes.

If you want to allow certain attributes on certain HTMLElements,
you'll have to use HTML::Scrubber's B<rules> configuration key.  The
default is to allow certain attributes on HTMLAnchorElement and
HTMLImageElement:

   rules   => [
       a   =>   {
                 '*'    => 0, # deny all attribs on A tags
                 href   => 1, # allow some attribs
                 name   => 1,
                 title  => 1,
                 target => 1
                },
       img =>   {
                 '*'    => 0, # deny all attribs on IMG tags
                 src    => 1, # allow some attribs
                 alt    => 1,
                 title  => 1,
                 width  => 1,
                 height => 1,
                },
  ]

=back

=head2 NOTE

Note that by the time the incoming HTML is passed to
C<html_scrubber()> the browser-specific markup (e.g. Gecko's BOLD tag)
has already been normalized (e.g. to STRONG).  So there's no need to
include B, EM or SPAN in the list of inline elements.  See
L<Krang::Markup>, L<Krang::Markup::IE>, L<Krang::Markup::Gecko> and
L<Krang::Markup::WebKit>.

Also note that in order to override the default behavior re: <script>
tags (which is to strip them), you must do the following:
    1. call HTML::Scrubber's special script() method, i.e.
           $scrubber->script(1);
    2. specify acceptable <script> attributes in the B<rules> arrayref, e.g.
           [..., script => { '*' => 1 }, ...]

=head2 WARNING

Be careful with your legacy data.  It may contain, say,
HTMLTableElements coded into some textarea 'paragraph' element.  If
you pass this through the default configuration of C<html_scrubber()>,
you will see the table in Xinha, but when done bulk editing,
C<html_scrubber()> will happily strip away the TABLE tags, leaving you
with the bare text content of all table cells concatenated without
whitespace!

     Know Your Data!

Also, nothing prevents users from typing a HTML table into a
'paragraph' textarea.  They will be surprised to see the TABLE tags
gone when passing this textarea's data through Xinha's bulk edit.

Why are tables disallowed? Because the available Xinha ignores a
decent way to handle tables.

Consider that the configuration or Xinha's B<toolbar> and the set of
B<allowed> HTMLElements are somewhat interdependent. No automagic is
provided to keep them streamlined. E.g., if you configure Xinha's
toolbar to not show the button for 'Ordered List', the 'ol' tag should
be disallowed - although users might of course paste ordered lists
in...

=cut

sub html_scrubber {
    my ($self, %arg) = @_;

    my @block_elements  = (qw(p h1 h2 h3 h4 h5 h6 ol ul hr li pre));
    my @inline_elements = (qw(a br em strong strike u sub sup));

    my $scrubber = HTML::Scrubber->new(

        # deny all tags and all attribs
        default => [0, {'*' => 0}],

        # however allow some tags
        allow => [@block_elements, @inline_elements],

        # and allow some attribs with A tags
        rules => [
            a => {
                '*'       => 0,    # deny all attribs on A tags
                href      => 1,    # allow some attribs
                name      => 1,
                title     => 1,
                target    => 1,
                class     => 1,
                _story_id => 1,
            },
            img => {
                '*'    => 0,       # deny all attribs on IMG tags
                src    => 1,       # allow some attribs
                alt    => 1,
                title  => 1,
                width  => 1,
                height => 1,
            },
            abbr => {
                '*'   => 0,        # deny all attribs on ABBR tags
                title => 1,
            },
            acronym => {
                '*'   => 0,        # deny all attribs on ACRONYM tags
                title => 1,
            },
            iframe => { '*' => 1}, # allow all attribs on IFRAME tags
##
## To allow tables, you might consider
##
##            table => {
##                      '*'         => 0, # deny all attribs on TABLE tags
##                      width       => 1, # allow some attribs
##                      border      => 1,
##                      summary     => 1,
##                      cellspacing => 1,
##                      cellpadding => 1,
##                     },
        ],
    );

    #
    # These defaults are in here to self-document
    #
    # remove comments
##    $scrubber->comment(0);
    # remove process instructions
##    $scrubber->process->(0);
    # remove HTMLScriptElements
##    $scrubber->script(0);
    # remove HTMLStyleElements
##    $scrubber->style(0);

    return $scrubber->scrub($arg{html});
}

=over

=item pkg('BulkEdit::Xinha::Config')->split_p_on_br();

If this method returns true, paragraphs will be split on
HTMLBRElements and each piece will be assigned to its own Krang
paragraph element. Defaults to true.

=cut

sub split_p_on_br { 1 }

=back

=cut

1;
