package Krang::Charset;
use strict;
use warnings;

use Krang::ClassLoader 'Conf';
use Krang::ClassFactory qw(pkg);

=head1 NAME

Krang::Charset - some handy utility methods for dealing with character sets

=head1 SYNOPSIS

    pkg('Charset')->is_utf8(); # depends on krang.conf

    pkg('Charset')->is_utf8('ISO 8859-1');  # false
    pkg('Charset')->is_utf8('UTF 8');       # true
    pkg('Charset')->is_utf8('utf-8');       # true

    # what does mysql want?
    pkg('Charset')->mysql_charset('UTF 8');         # utf8
    pkg('Charset')->mysql_charset('ISO 8859-1');    # latin1

=head1 DESCRIPTION

This class just provides a collection of methods that are useful
when operating on character sets.

=head1 INTERFACE

=head2 C<< Krang::Charset->is_utf8([$charset]) >>

Returns true if the character set looks like UTF-8. Defaults to using
the configured characters set if none is given.

=cut

sub _munge_charset {
    my $charset = lc shift;
    $charset =~ s/\s*//g; # remove ws
    $charset =~ s/-//g;   # remove hyphens
    return $charset;
}


sub is_utf8 {
    my ($class, $charset ) = @_;
    $charset ||= pkg('Conf')->get('Charset') || '';
    return _munge_charset($charset) eq 'utf8';
}

=head2 C<< Krang::Charset->mysql_charset([$charset])

This method tries to convert the given charset into something that MySQL
can understand. Defaults to using the configured characters set if none
is given.

=cut

# try and convert it to something that mysql likes
my %MYSQL_MAP = (
    iso88591    => 'latin1',
    iso88592    => 'latin2',
    iso88598    => 'hebrew',
    iso88599    => 'latin5',
    cp1252      => 'latin1',
    windows1252 => 'latin1',
);

sub mysql_charset {
    my ($pkg, $charset) = @_;
    $charset ||= pkg('Conf')->get('Charset') || '';
    $charset = _munge_charset($charset);

    return $MYSQL_MAP{$charset} || $charset;
}



1;
