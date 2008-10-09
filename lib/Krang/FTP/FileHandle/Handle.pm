package Krang::FTP::FileHandle::Handle;

use strict;
use warnings;

use base 'IO::Handle';

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader Log => qw(debug info critical);
use Time::Piece;

=head1 NAME
    
Krang::FTP::FileHandle::Handle - IO::Handle class for Krang::FTP::FileHandle

=head1 SYNOPSIS

See usage in Krang::FTP::FileHandle

=head1 DESCRIPTION

This class provides a filehandle interface to a media/template object, is based 
on IO::Handle and is used interbnally by L<Krang::FTP::FileHandle>.

=head1 INTERFACE

Overrides IO::Handle methods syswrite and close().

Takes a media/template object and type as arguments.


=head2 METHODS

=over

=item Krang::FTP::FileHandle::Handle->new($object, $type)

Creates a new Krang::FTP::FileHandle::Handle object.  Takes 4 required 
arguments: the Krang::Media or Krang::Template object, and the $type ("media" 
or "template") of the represented object.

=cut

sub new {
    my $class  = shift;
    my $object = shift;
    my $type   = shift;

    my $self = bless {object => $object, type => $type, buffer => ''}, $class;

    return $self;
}

sub syswrite {
    my $self = shift;
    my ($data, $length, $offset) = @_;
    $self->{buffer} .= $data;

    return $length;
}

sub close {
    my $self   = shift;
    my $object = $self->{object};
    my $type   = $self->{type};

    if ($type eq 'media') {

        # checkout and version media if not a new media
        if ($object->media_id) {
            $object->checkout();
        }

        my $filename = $object->filename();

        $object->upload_file(
            filename   => $filename,
            filehandle => (new IO::Scalar \$self->{buffer})
        );
    } else {    # if template
        if ($object->template_id) {
            $object->checkout();
        }

        # save new content
        $object->content($self->{buffer});
    }

    $object->save();
    $object->checkin();

    # deploy, preview, publish object as needed
    if ($type eq 'template') {
        $object->deploy;
    } else {
        $object->preview;
        $object->publish;
    }

    return 1;

}

# Override IO::File->print so each line is saved to the internal buffer
# and ultimately saved when close() is called. This makes ASCII transfers
# work because Net::FTPServer calls file->print on this handle for each
# line, and if we don't override print, this will be fatal.
sub print {
    my $self         = shift;
    my $string2print = shift;
    $self->{buffer} .= $string2print;    # add string to buffer
}

=head1 SEE ALSO

Net:FTPServer::FileHandle

L<Krang::FTP::Server>

L<Krang::FTP::DirHandle>

L<Krang::FTP::FileHandle>

=cut

1;

