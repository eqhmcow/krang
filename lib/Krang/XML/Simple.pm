package Krang::XML::Simple;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use XML::Simple ();
use MIME::Base64 qw(decode_base64);
use Encode qw(decode_utf8);
use Krang::ClassLoader 'Charset';

use base 'Exporter';
our @EXPORT_OK = qw(XMLin);

=head1 NAME

Krang::XML::Simple - XML::Simple sub-class with auto Base64 decoding

=head1 SYNOPSIS

  use Krang::ClassLoader XML::Simple => qw(XMLin);
  my $data = XMLin($xml, @args);

=head1 DESCRIPTION

This module is a sub-class of XML::Simple which adds one feature.  It
will automatically decode Base64 character content prefixed by the
C<!!!BASE64!!!> marker.  This is the marker emited by
L<Krang::XML::Writer> when characters must be encoded for output.

=head1 INTERFACE

Same as L<XML::Simple>.

=cut

sub XMLin {
    my $data = XML::Simple::XMLin(@_);
    _fix($data);

    return $data;
}

sub _fix {
    my $data = shift;
    my $type = ref $data;
    return unless $type;

    if ($type eq 'HASH') {
        foreach my $val (values %$data) {
            if( ref $val ) {
                _fix($val);
            } else {
                $val = _fix_scalar($val);
            }
        }
    } elsif ($type eq 'ARRAY') {
        foreach my $val (@$data) {
            if( ref $val ) {
                _fix($val);
            } else {
                $val = _fix_scalar($val);
            }
        }
    } else {
        croak("What am I supposed to do with '$type'?");
    }
}

sub _fix_scalar {
    my $val = shift;
    if ($val =~ s/^!!!BASE64!!!//) {
        $val = decode_base64($val);
    }
    $val = decode_utf8($val) if pkg('Charset')->is_utf8;
    return $val;
}

1;
