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

    # print to STDOUT with the correct encoding
    pkg('IO')->print($some_string);

    # print to STDOUT with a trailing newline with the correct encoding
    pkg('IO')->say($some_string);

    # print to STDERR with a trailing newline with the correct encoding
    pkg('IO')->warn($some_string);

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
    my ($pkg, undef, $mode, $path) = @_;
    my $charset = Charset();
    $mode .= ":encoding($charset)" if $charset;
    return open($_[1], $mode, $path);
}

=head2 io_file

This returns a new L<IO::File> object and acts just like single
arg form of C<IO::File::new()>.

To read/write a file in binary mode (by-passing the Charset directive)
pass the optional 'binary' argument in.

    my $io = pkg('IO')->io_file(">/some/file");

    my $io = pkg('IO')->io_file(">/some/file", 'binary' => 1);

=cut

sub io_file {
    my ($pkg, $file, %arg) = @_;
    my $charset = Charset();

    if ($charset and not $arg{binary}) {

        # see if the mode is specified
        my $mode;
        if ($file =~ /^\s*(<|>|>>)\s*(.*)/) {
            $mode = $1;
            $file = $2;
        } else {

            # it's an implicit read
            $mode = '<';
        }

        $mode .= ":encoding($charset)";

        return IO::File->new($file, $mode);
    } else {
        return IO::File->new($file);
    }
}

=head2 print

Prints a message to C<STDOUT> (or the default C<select()>ed file handle)
with the correct character set encoding.

=cut

sub print {
    my ($pkg, $string) = @_;
    my $charset = Charset();
    if( my $charset = Charset() ) {
        binmode(select(), ":encoding($charset)");
    }
    print $string;
}

=head2 say

Prints a message to C<STDOUT> (or the default C<select()>ed file handle)
with a trailing newline added, with the correct character set encoding.

=cut

sub say {
    my ($pkg, $string) = @_;
    $pkg->print("$string\n");
}

=head2 warn

Prints a message to C<STDERR> with a trailing newline added.

=cut

sub warn {
    my ($pkg, $string) = @_;
    my $charset = Charset();
    if( my $charset = Charset() ) {
        binmode(STDERR, ":encoding($charset)");
    }
    print STDERR "$string\n";
}

1;
