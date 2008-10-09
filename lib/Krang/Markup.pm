package Krang::Markup;
use warnings;
use strict;

=head1 NAME

Krang::Markup - Base class for browser-specific WYSIWYG HTML filtering

=head1 SYNOPSIS

Krang::Markup - Base class for browser-specific WYSIWYG HTML filtering

=head1 DESCRIPTION

Different browsers use different HTML tags to manage basic markup like
bold, italic, underline, strike-through, subscript and superscript.
To normalize the database content across the usage of different
browsers, the HTML must be filtered accordingly when going to and
coming from browser WYSIWYG areas.

=head2 Definition

A "normalized tag" is the HTML tag stored in the database and
published on the net.

=head2 Example

Let's take BOLD text as an example. The normalized tag is STRONG.

Boldifying text in IE effectively inserts the C<STRONG> tag.

Gecko, however, inserts the C<B> tag, and WebKit wraps the text with a
C<SPAN> tag having its style attribute set to C<font-weight: bold>.

When going to Gecko or WebKit the C<STRONG> tag therefore has to be
replaced with what the WYSIWYG commands of those browsers understand.
And when coming from them, the normalized version has to be restored.

This module provides mockups for methods accomplishing this task.

=head1 INTERFACE

Subclasses must implement the following class methods:

=over

=item pkg('Markup::Subclass')->db2browser_map()

This method must return a list mapping normalized tags to their
browser-specific equivalent.  It is to be called by C<db2browser()>.

=cut

sub db2browser_map {
    croak(__PACKAGE__ . '->db2browser_map() must be defined in a subclass of Krang::Markup');
}

=item pkg('Markup::Subclass')->browser2db_map()

This method must return a list mapping browser-specific HTML tags to
their normalized equivalent.  It is to be called by C<browser2db()>.

=cut

sub browser2db_map {
    croak(__PACKAGE__ . '->browser2db_map() must be defined in a subclass of Krang::Markup');
}

=item pkg('Markup::Subclass')->db2browser(html => $html)

This method replaces normalized tags with their browser-specific
equivalent using the mappings provided by C<db2browser_map()>.

It is passed the normalized HTML and returns a string with
those mappings applied to it.

Due to strangeness of the internally used L<HTML::Element> module this
method must B<not> directly return the modified HTML. Instead return
the HTML returned by $pkg->tidy_up_after_treebuilder(tree => $tree) -
the argument $tree being a L<HTML::TreeBuilder> object.

=cut

sub db2browser {
    croak(__PACKAGE__ . '->db2browser() must be defined in a subclass of Krang::Markup');
}

=item pkg('Markup::Subclass')->browser2db(html => $html)

This method replaces browser-specific tags with their normalized
equivalent according to the mappings provided by C<browser2db_map()>

It is passed the HTML coming from the browser and returns a string
with those mappings applied.

Due to strangeness of the internally used L<HTML::Element> module this
method must B<not> directly return the modified HTML. Instead return
the HTML returned by $pkg->tidy_up_after_treebuilder(tree => $tree) -
the argument $tree being a L<HTML::TreeBuilder> object.

=cut

sub browser2db {
    croak(__PACKAGE__ . '->browser2db() must be defined in a subclass of Krang::Markup');
}

=item pkg('Markup::Subclass')->tidy_up_after_treebuilder($html_tree_object)

This method should be called at the end of the two mapping methods
C<db2browser()> and C<browser2db()>.  It chops the BODY tag
L<HTML::TreeBuilder> wraps around the passed-in HTML, removes the
trailing newline added by L<HTML::Element>'s C<as_HTML()>, destroys the
tree object and finally returns the HTML.

=cut

sub tidy_up_after_treebuilder {
    my ($pkg, %arg) = @_;
    my $tree = $arg{tree};

    # return only the children of the HTML body
    my $body = $tree->find_by_tag_name('body')->as_HTML('<>&', undef, {});

    # chop implicit body tag
    $body =~ s/^\s*<body>//is;
    $body =~ s/<\/body>\s*$//is;

    # chop newline added by HTML::Element's as_HTML() method
    $body =~ s/\n$//;

    # cleanup
    $tree->delete();

    # return filtered HTML
    return $body;
}

=item pkg('Markup::Subclass')->remove_junk(\$html)

This method does:

 remove tags w/o content inside
 remove adjacent closing/opening tags while preserving whitespace in between
 remove excess whitespace
 remove leading whitespace
 remove trailing whitespace
 remove leading BR tags
 remove trailing BR tags

It must be passed a scalar reference to a string containing the HTML
to be cleaned.

=cut

sub remove_junk {
    my ($self, $html) = @_;

    $$html =~ s/<([^>]+)>\s*<\/\1>//gs;        # remove tags w/o content inside
    $$html =~ s/<\/([^>]+)>(\s*)<\1>/$2/gs;    # remove adjacent closing/opening tags
    $$html =~ s/(\s|&nbsp;)+/ /gs;             # remove excess whitespace
    $$html =~ s/^\s+//sg;                      # remove leading whitespace
    $$html =~ s/\s+$//sg;                      # remove trailing whitespace
    $$html =~ s/^(<\/?br[^>]*>)+//gsi;         # remove leading BR tags
    $$html =~ s/(<\/?br[^>]*>)+$//gsi;         # remove trailing BR tags
}

1;
