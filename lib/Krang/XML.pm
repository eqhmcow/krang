package Krang::XML;
use strict;
use warnings;

use XML::Writer;
use IO::Scalar;
use Carp qw(croak);
use XML::Simple qw(XMLin);

=head1 NAME

Krang::XML - XML utility class

=head1 SYNOPSIS

  # get a new XML::Writer object, setup to write into $xml
  $writer = Krang::XML->writer(string => \$xml);

=head1 DESCRIPTION

This module provides methods to assist in handling XML data in Krang.
Their primary purpose is to make writing the serialize_xml() and
deserialize_xml() methods required by Krang::DataSet easier.

=head1 INTERFACE

=over 4

=item C<< $writer = Krang::XML->writer(string => \$xml) >>

=item C<< $writer = Krang::XML->writer(fh => $fh) >>

Creates an XML::Writer object which will write it's output to either a
string or a filehandle.  The DATA_MODE and DATA_INDENT options in
XML::Writer are automatically turned on.

=cut

sub writer {
    my ($pkg, %args) = @_;

    my $fh;
    if ($args{fh}) {
        $fh = $args{fh};
    } elsif ($args{string}) {
        $fh = IO::Scalar->new($args{string});
    } else {
        croak("Missing fh or string arg.");
    }

    return XML::Writer->new(OUTPUT      => $fh,
                            DATA_MODE   => 1,
                            DATA_INDENT => 4);
}

=item C<< $data = Krang::XML->simple(xml => $xml) >>

Calls XML::Simple::XMLin() on the provided xml text and returns the
result.  Any additional options are passed along to XMLin().  The
default for C<keyattr> is C<[]> instead of the absurd default.

=cut

sub simple {
    my ($pkg, %args) = @_;
    my $xml = delete $args{xml};
    $args{keyattr} ||= [];
    return XMLin($xml, %args);
}

=back

=cut


1;
