package Krang::Charset;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader Conf => qw(Charset);

=head1 NAME

Krang::Charset - some handy utility methods for dealing with character sets

=head1 SYNOPSIS

    pkg('Charset')->is_utf8();

    pkg('Charset')->is_latin();

=head1 DESCRIPTION

This class just provides a collection of methods that are useful
when operating on character sets.

=head1 INTERFACE

=head2 C<< Krang::Charset->is_utf8([$charset]) >>

Returns true if the character set looks like UTF-8.  Defaults to using
the configured characters set if none is given.

=cut

sub is_utf8 {
    my ($class, $charset ) = @_;
    $charset ||= Charset();
    $charset = lc $charset;
    return $charset eq 'utf-8' or $charset eq 'utf8';
}

=head2 C<< Krang::Charset->is_latin >>

Returns true if the character set looks like an ISO-8859 character set.
Defaults to using the configured characters set if none is given.

=cut

sub is_latin {
    my ($class, $charset ) = @_;
    $charset ||= Charset();
    $charset = lc $charset;
    return index($charset, 'iso-8859') == 0 or index($charset, 'iso8859') == 0;
}


1;
