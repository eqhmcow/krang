package Krang::Charset;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader Conf => qw(Charset);

=head1 NAME

Krang::Charset - some handy utility methods for dealing with character sets

=head1 SYNOPSIS

    pkg('Charset')->is_utf8(); # depends on krang.conf

    pkg('Charset')->is_utf8('ISO 8859-1');  # false
    pkg('Charset')->is_utf8('UTF 8');       # true
    pkg('Charset')->is_utf8('utf-8');       # true

=head1 DESCRIPTION

This class just provides a collection of methods that are useful
when operating on character sets.

=head1 INTERFACE

=head2 C<< Krang::Charset->is_utf8([$charset]) >>

Returns true if the character set looks like UTF-8.  Defaults to using
the configured characters set if none is given.

=cut

my $MUNGED;
sub _munge_charset {
    my $charset = lc shift;
    $charset =~ s/\s*//; # remove ws
    $charset =~ s/-//;   # remove hyphens
    return $charset;
}
BEGIN {
    $MUNGED = _munge_charset(Charset());
}


sub is_utf8 {
    my ($class, $charset ) = @_;
    return ( $charset ? _munge_charset($charset) : $MUNGED ) eq 'utf8';
}

1;
