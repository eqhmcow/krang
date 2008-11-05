package Krang::Markup::WebKit;
use warnings;
use strict;

use Krang::ClassLoader base => qw(Markup);

use Krang::ClassLoader Log => qw(debug);

use HTML::TreeBuilder;
use HTML::Element;
use HTML::TokeParser;
use Data::Dumper;

=head1 NAME

Krang::Markup::WebKit - WYSIGWYG HTML filtering for WebKit browsers

=head1 SYNOPSIS

Subclass of Krang::Markup for browsers based on WebKit

=head1 DESCRIPTION

See L<Krang::Markup>

=head1 INTERFACE

See L<Krang::Markup>

=over

=item pkg('Markup::WebKit')->db2browser_map()

This method returns a list of markup mappings from the version stored
in the DB to a version understood by WebKit's WYSIWYG commands.

=cut

sub db2browser_map {
    return {

        # markup => inline CSS for SPAN.Apple-style-span
        strong => 'font-weight: bold',
        em     => 'font-style: italic',
        u      => 'text-decoration: underline',
        strike => 'text-decoration: line-through',
        sub    => 'vertical-align: sub',
        sup    => 'vertical-align: super'
    };
}

=item pkg('Markup::WebKit')->browser2db_map()

This method returns a list of markup mappings from the version
understood by WebKit's WYSIWYG commands to the version stored in the
DB. 

=cut

sub browser2db_map {
    return {

        # canonical form of inline CSS => markup tag
        font_weight_normal           => 'just_a_placeholder_for_true',
        font_weight_bold             => 'strong',
        font_style_normal            => 'just_a_placeholder_for_true',
        font_style_italic            => 'em',
        text_decoration_underline    => 'u',
        text_decoration_line_through => 'strike',
        vertical_align_sub           => 'sub',
        vertical_align_super         => 'sup',
    };
}

=item pkg('Markup::WebKit')->db2browser(html => $html)

This method replaces normalized tags with their WebKit-specific
equivalent using the mappings provided by C<db2browser_map()>.

It is passed the normalized HTML and returns a string with
those mappings applied to it.

=cut

sub db2browser {
    my ($pkg, %arg) = @_;

    my $html      = $arg{html};
    my $style_for = $pkg->db2browser_map();
    my @open_tags = ();
    my @output    = ();

    my $tmp = '^(' . join('|', keys(%$style_for)) . ')$';
    my $tag_regexp = qr($tmp);

    # proceed by tokens
    my $p = HTML::TokeParser->new(\$html);

    while (my $token = $p->get_token) {

        debug(__PACKAGE__ . "->db2browser() - Token:\n  " . Dumper($token));

        if ($token->[0] eq 'S') {
            $pkg->db2browser_start_tag($token, \@open_tags, \@output, $tag_regexp);
        } elsif ($token->[0] eq 'E') {
            $pkg->db2browser_end_tag($token, \@open_tags, \@output, $tag_regexp);
        } elsif ($token->[0] eq 'T') {
            $pkg->db2browser_text_node($token, \@open_tags, \@output, $style_for);
        } else {

            # discard comments, CData and processor instructions
        }
    }

    # put the pieces together
    return $html = join('', @output);
}

=item pkg('Markup::WebKit')->browser2db(html => $html)

This method replaces WebKit-specific tags with their normalized
equivalent according to the mappings provided by C<browser2db_map()>

It is passed the HTML coming from the browser and returns a string
with those mappings applied.

=cut

sub browser2db {
    my ($pkg, %arg) = @_;

    my $html       = $arg{html};
    my $markup_for = $pkg->browser2db_map();
    my @open_tags  = ();
    my @output     = ();

    # proceed by tokens
    my $p = HTML::TokeParser->new(\$html);

    while (my $token = $p->get_token) {

        debug(__PACKAGE__ . "->browser2db() - Token:\n  " . Dumper($token));

        if ($token->[0] eq 'S') {
            $pkg->browser2db_start_tag($token, \@open_tags, \@output, $markup_for);
        } elsif ($token->[0] eq 'E') {
            $pkg->browser2db_end_tag($token, \@open_tags, \@output);
        } elsif ($token->[0] eq 'T') {
            $pkg->browser2db_text_node($token, \@open_tags, \@output, $markup_for);
        } else {

            # discard comments, CData and processor instructions
        }
    }

    # put the pieces together
    $html = join('', @output);

    # maybe some further cleaning
    $pkg->remove_junk(\$html);

    # uff!
    return $html;
}

#
# Parser callbacks
#

sub browser2db_start_tag {
    my ($pkg, $token, $open_tags, $output, $markup_for) = @_;

    if ($token->[1] eq 'span') {

        # the interesting stuff to tweak
        my $style  = $token->[2]{style};
        my @styles = ();

        # normalize the styles' string
        if ($style) {
            @styles = grep {
                $markup_for->{$_}    # discard undesired styles
              } map {
                s/\s+//g;            # chop whitespace
                s/\W/_/g;            # replace non-word chars with underscores
                $_;                  # return the result
              } grep {
                $_
              } split(';', $style);

            debug(__PACKAGE__ . "->browser2db_start_tag() - Span Styles: " . Dumper(\@styles));
        }

        # and record the them as open tags
        push @$open_tags, \@styles;
    } else {

        # other HTMLElement start tag: copy to output
        push @$output, $token->[4];
    }
}

sub browser2db_end_tag {
    my ($pkg, $token, $open_tags, $output) = @_;

    if ($token->[1] eq 'span') {

        # adjust the list of open tags
        pop(@$open_tags);
    } else {

        # copy to output
        push @$output, $token->[2];
    }
}

sub browser2db_text_node {
    my ($pkg, $token, $open_tags, $output, $markup_for) = @_;

    # the text node
    my $text = $token->[1];

    # list of currently active styles
    my @styles = map { ref($_) ? @$_ : $_ } @$open_tags;

    debug(__PACKAGE__ . "->browser2db_text_node() - Unfiltered open tags:\n  " . Dumper(\@styles));

    # filter the style list for oppositions
    for my $attrib ([qw(weight_normal weight_bold)], [qw(style_normal style_italic)]) {

        my $saw_normal = 0;

        for (my $i = $#styles ; $i >= 0 ; --$i) {
            if ($styles[$i] eq "font_$attrib->[0]") {
                splice(@styles, $i, 1);
                $saw_normal = 1;
                next;
            }
            if ($styles[$i] eq "font_$attrib->[1]" && $saw_normal) {
                splice(@styles, $i, 1);
                next;
            }
        }
    }

    # uniq'ify 'em styles
    my %uniq = ();
    @uniq{@styles} = ();

    # make the new node(s) and copy to output
    push @$output, $pkg->make_nodes($text, [keys %uniq], $markup_for);

    debug(  __PACKAGE__
          . "->browser2db_text_node() - Created node\n  Text: $text\n  Tags: "
          . Dumper(\@styles));
}

sub db2browser_start_tag {
    my ($pkg, $token, $open_tags, $output, $tag_regexp) = @_;

    if ($token->[1] =~ $tag_regexp) {
        push @$open_tags, $1;
    } else {

        # other HTMLElement start tag: copy to output
        push @$output, $token->[4];
    }
}

sub db2browser_end_tag {
    my ($pkg, $token, $open_tags, $output, $tag_regexp) = @_;

    if ($token->[1] =~ $tag_regexp) {

        # close the last open tag
        pop(@$open_tags);
    } else {

        # copy to output
        push @$output, $token->[2];
    }
}

sub db2browser_text_node {
    my ($pkg, $token, $open_tags, $output, $style_for) = @_;

    # the text node
    my $text = $token->[1];

    # the SPAN's style attrib according to currently open markup tags
    my $style = @$open_tags ? join('; ', map { $style_for->{$_} } @$open_tags) : '';

    # one more piece
    push @$output, ($style ? qq{<span style="$style">$text</span>} : $text);

    debug(__PACKAGE__ . "->db2browser_text_node() - Open tags:\n  " . Dumper($open_tags));
    debug(
        __PACKAGE__ . "->db2browser_text_node() - Resulting node\n  Text: $text\n  Style: $style");
}

sub make_nodes {
    my ($pkg, $text, $styles, $markup_for) = @_;

    # start tag(s)
    my $html = join('', map { "<$markup_for->{$_}>" } @$styles);

    # text
    $html .= $text;

    # end tag(s)
    $html .= join('', map { "</$markup_for->{$_}>" } reverse @$styles);

    return $html;
}

1;
