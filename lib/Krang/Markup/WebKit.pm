package Krang::Markup::WebKit;
use warnings;
use strict;

use HTML::TreeBuilder;
use HTML::Element;

use Krang::ClassLoader base => qw(Markup);

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
        strong => {'font-weight'     => 'bold'},
        em     => {'font-style'      => 'italic'},
        u      => {'text-decoration' => 'underline'},
        strike => {'text-decoration' => 'line-through'},
        sub    => {'vertical-align'  => 'sub'},
        sup    => {'vertical-align'  => 'super'}
    };
}

=item pkg('Markup::WebKit')->browser2db_map()

This method returns a list of markup mappings from the version
understood by WebKit's WYSIWYG commands to the version stored in the
DB.

=cut

sub browser2db_map {
    return {
        'bold'         => 'strong',
        'italic'       => 'em',
        'underline'    => 'u',
        'line-through' => 'strike',
        'sub'          => 'sub',
        'super'        => 'sup',
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

    # build the tag regexp
    my $map    = $pkg->db2browser_map();
    my $tmp    = '^(?:' . join('|', keys(%$map)) . ')$';
    my $regexp = qr($tmp);

    # build the tree
    my $t = HTML::TreeBuilder->new_from_content($arg{html});
    $t->elementify;

    while (my $orig = $t->look_down("_tag" => $regexp)) {

        # remember style for the will-be-span
        my %style = (%{$map->{$orig->tag}});

        my $child          = undef;
        my $content_parent = $orig;

        # maybe first child of this markup tag is another markup tag;
        # if so, pack it in the same span with multiple style properties
        while (
            $child = $content_parent->look_down(
                sub {
                    $_[0]->tag ne $content_parent->tag and $_[0]->tag =~ $regexp;
                }
            )
          )
        {

            # consider only first child
            last unless $child->pindex == 0;

            # remember additional style for will-be-span
            %style = (%style, %{$map->{$child->tag}});

            # recurse
            $content_parent = $child;
        }

        # build the span's style attrib
        my $style = join('; ', map { "$_: $style{$_}" } keys %style);

        # create the span,
        my $repl = HTML::Element->new('span', 'style' => $style);

        # replace original tag(s) with span and insert its/their content
        $orig->replace_with($repl);
        $repl->push_content($content_parent->content_list);

        # cleanup
        $orig->delete();
    }

    return $pkg->tidy_up_after_treebuilder(tree => $t);
}

=item pkg('Markup::WebKit')->browser2db(html => $html)

This method replaces WebKit-specific tags with their normalized
equivalent according to the mappings provided by C<browser2db_map()>

It is passed the HTML coming from the browser and returns a string
with those mappings applied.

=cut

sub browser2db {
    my ($pkg, %arg) = @_;

    # build the tag regexp
    my $map    = $pkg->browser2db_map();
    my $tmp    = '(' . join('|', keys(%$map)) . ')';
    my $regexp = qr($tmp);

    # build the tree
    my $t = HTML::TreeBuilder->new_from_content($arg{html});
    $t->elementify;

    # look for SPAN tags with a style attrib
    while (
        my $span = $t->look_down(
            "_tag"  => "span",
        )
      )
    {

        my $repl  = undef;
        my $child = undef;
        my $style = $span->attr('style');

        # remove SPANs with empty style attrib
        unless ($style) {
            $span->replace_with($span->content_list)->delete;
            next;
        }

        # make (nested) tags for style props
        while ($style =~ /$regexp/g) {
            my $tag = $map->{$1};

            my $elm = HTML::Element->new($tag);

            if ($child) {
                $child->push_content($elm);
            } else {
                $repl = $elm;
            }

            $child = $elm;
        }

        # replace the span
        $span->replace_with($repl);
        $child->push_content($span->content_list);

        # cleanup
        $span->delete();

    }

    return $pkg->tidy_up_after_treebuilder(tree => $t);
}

1;
