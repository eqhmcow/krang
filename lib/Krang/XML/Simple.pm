package Krang::XML::Simple;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use XML::Simple ();
use MIME::Base64 qw(decode_base64);

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
            _fix($val) if ref $val;
            if ($val =~ s/^!!!BASE64!!!//) {
                $val = decode_base64($val);
            }
        }
    } elsif ($type eq 'ARRAY') {
        foreach my $val (@$data) {
            _fix($val) if ref $val;
            $val = decode_base64($val) if $val =~ s/^!!!BASE64!!!//;
        }
    } else {
        croak("What am I supposed to do with '$type'?");
    }
}

1;
