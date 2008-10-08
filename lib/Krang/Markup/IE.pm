package Krang::Markup::IE;
use warnings;
use strict;

use HTML::TreeBuilder;
use HTML::Element;

use Krang::ClassLoader base => qw(Markup);

=head1 NAME

Krang::Markup::IE - WYSIGWYG HTML filtering for Internet Explorer

=head1 SYNOPSIS

Subclass of Krang::Markup for Internet Explorer

=head1 DESCRIPTION

See L<Krang::Markup>

=head1 INTERFACE

See L<Krang::Markup>

=over

=item pkg('Markup::IE')->db2browser_map()

This method returns a list of markup mappings from the version stored
in the DB to a version understood by Internet Explorer's WYSIWYG commands.

=cut

sub db2browser_map { () }

=item pkg('Markup::IE')->browser2db_map()

This method returns a list of markup tag mappings from the version
understood by Internet Explorer's WYSIWYG commands to the version
stored in the DB.

=cut

sub browser2db_map { () }

=item pkg('Markup::IE')->db2browser(html => $html)

This method replaces normalized tags with their IE-specific
equivalent using the mappings provided by C<db2browser_map()>.

It is passed the normalized HTML and returns a string with
those mappings applied to it.

=cut

sub db2browser {
    my ($pkg, %arg) = @_;

    # get the map
    my %map = $pkg->db2browser_map();

    # no mappings: return as-is
    return $arg{html} unless %map;

    # return with mappings applied
    return $pkg->_replace_tags(%arg, map => \%map);
}

=item pkg('Markup::IE')->browser2db(html => $html)

This method replaces IE-specific tags with their normalized
equivalent according to the mappings provided by C<browser2db_map()>

It is passed the HTML coming from the browser and returns a string
with those mappings applied.

=cut

sub browser2db {
    my ($pkg, %arg) = @_;

    # get the map
    my %map = $pkg->browser2db_map();

    # no mappings
    return $arg{html} unless %map;

    # return with mappings applied
    return $pkg->_replace_tags(%arg, map => \%map);
}

#
# the replacement workhorse
#
sub _replace_tags {
    my ($pkg, %arg) = @_;

    # build tag regexp
    my $map    = $arg{map};
    my $tmp    = '^(?:' . join('|', keys(%$map)) . ')$';
    my $regexp = qr($tmp);

    # build HTML tree
    my $t = HTML::TreeBuilder->new_from_content($arg{html});
    $t->elementify;

    # replace tags
    while(my $element = $t->look_down("_tag" => $regexp)) {
        $element->tag($map->{$element->tag});
    }

    return $pkg->tidy_up_after_treebuilder(tree => $t);
}

=back

=cut

1;
