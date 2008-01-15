package Krang::XML::Writer;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use base 'XML::Writer';
use MIME::Base64 qw(encode_base64);
use Krang::ClassLoader 'Charset';
use Encode qw(encode_utf8);

=head1 NAME

Krang::XML::Writer - XML::Writer sub-class with auto Base64 encoding

=head1 SYNOPSIS

  use Krang::ClassLoader 'XML::Writer';
  my $writer = pkg('XML::Writer')->new();
  # ... same as XML::Writer

=head1 DESCRIPTION

This module is a sub-class of XML::Writer which adds one feature.  It
will automatically encode XML-illegal character content as Base64 and
add the C<!!!BASE64!!!> marker.  This marker is used by
Krang::XML::Simple to automatically decode Base64 data.

=head1 INTERFACE

Same as L<XML::Writer>.

=head1 CAVEAT

This sub-class won't work if you make multiple calls to characters()
with binary data.  For example:

  $writer->character("...");
  $writer->character("...");

Won't work.  Instead, combine your character content into a single
call:

  $writer->character("..." . "...");

Or just use the dataElement() helper function.  This might be fixed
someday if it becomes a problem.

=cut

sub dataElement {
    my ($self, $name, $value, %attr) = @_;
    foreach my $val (values %attr) {
        _fix_val(\$val);
    }
    $self->SUPER::dataElement($name, $value, %attr);
}

sub startTag {
    my ($self, $name, %attr) = @_;
    foreach my $val (values %attr) {
        _fix_val(\$val);
    }
    $self->SUPER::startTag($name, %attr);
}

sub characters {
    my ($self, $value) = @_;
    return unless defined $value;
    _fix_val(\$value);
    $self->SUPER::characters($value);
}

sub _fix_val {
    return unless defined ${$_[0]} and 
      (${$_[0]} =~ /[^\x20-\x7E\n\t]/s or 
       ${$_[0]} =~ /^\s+$/ or
       ${$_[0]} =~ /^!!!BASE64!!!/);

    ${$_[0]} = encode_utf8(${$_[0]}) if pkg('Charset')->is_utf8;
    ${$_[0]} = '!!!BASE64!!!' . encode_base64(${$_[0]}, "");
}

1;
