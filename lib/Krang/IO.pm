package Krang::IO;
use strict;
use warnings;

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader Conf => qw(Charset);
use IO::File;

=head1 NAME

Krang::IO - abstract away any IO operations that need to be Charset-aware

=head1 SYNOPSIS

    my $FH;
    # for writing
    pkg('IO')->open($FH, '>', '/some/file')
        or die "Could not open for writing: $!";

    # for reading
    pkg('IO')->open($FH, '<', '/some/file')
        or die "Could not open for reading: $!";

    # get an IO::File object with the right encoding
    my $io = pkg('IO')->io_file(">/some/file");

=head1 DESCRIPTION

Krang can be setup to run on multiple character sets. A lot of the common
character sets don't need anything really special to interact with the files
but some (like UTF-8) do.

This module provides the necessary abstraction so that for the most part
you don't need to worry about that.

=head1 INTERFACE

=head2 open

This works like Perl's built-in open (the 3 argument version), but will
set the appropriate encoding based on the Charset.

    my $FH;
    # for writing
    pkg('IO')->open($FH, '>', '/some/file')
        or die "Could not open for writing: $!";

=cut

sub open {
    my ($pkg, $fh, $mode, $path) = @_;
    my $charset = Charset();
    $mode .= ":encoding($charset)" if $charset;
    return open($fh, $mode, $path);
}

=head2 io_file

This returns a new L<IO::File> object and acts just like single
arg form of C<IO::File::new()>.

    my $io = pkg('IO')->io_file(">/some/file");

=cut

sub io_file {
    my ($pkg, $file) = @_;
    my $charset = Charset();

    if ($charset) {

        # see if the mode is specified
        my $mode;
        if ($file =~ /^\s*(<|>|>>)\s*(.*)/) {
            $mode = $1;
            $file = $2;
        } else {

            # it's an implicit read
            $mode = '<';
        }

        $mode .= ":encoding($charset)" if $charset;

        return IO::File->new($file, $mode);
    } else {
        return IO::File->new($file);
    }
}

1;
