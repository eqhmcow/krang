package Krang::FTP::FileHandle;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader DB => qw(dbh);
use Krang::ClassLoader 'Conf';
use Krang::ClassLoader Log => qw(debug info critical);
use Net::FTPServer::FileHandle;
use Krang::ClassLoader 'FTP::DirHandle';
use Krang::ClassLoader 'FTP::FileHandle::Handle';
use IO::Scalar;
use IO::File;
use Time::Piece;
use Time::Piece::MySQL;

################################################################################
# Inheritance
################################################################################
our @ISA = qw(Net::FTPServer::FileHandle);

=head1 NAME
    
Krang::FTP::FileHandle - Virtual FTP Server FileHandle

=head1 SYNOPSIS

None.

=head1 DESCRIPTION

This module provides a file handle object for use by
Krang::FTP::Server.

=head1 INTERFACE

This module inherits from Net::FTPServer::FileHandle and overrides the
required methods.  This class is used internally by Krang::FTP::Server.

=head2 METHODS

=over

=item Krang::FTP::FileHandle->new($ftps, $object, $type, $category_id)

Creates a new Krang::FTP::FileHandle object.  Requires 4 arguments:
the Krang::FTP::Server object, the Krang::Media or Krang::Template object,
the $type (media or template) of the represented object,
and the and the category_id which this file is in.

=cut

sub new {
    my $class   = shift;
    my $ftps    = shift;
    my $object  = shift;
    my $type    = shift;
    my $category_id = shift;

    my $filename =  $object->filename();

    # Create object.
    my $self = Net::FTPServer::FileHandle->new ($ftps, $filename);

    $self->{object}         = $object;
    $self->{category_id}    = $category_id;
    $self->{type}           = $type;
    $self->{filename}       = $filename;

    return bless $self, $class;
}

=item open($mode)

This method opens this template/media object for access using the provided
mode ('r', 'w' or 'a').  The method returns an IO::Scalar object that
will be used by Net::FTPServer to access the template/media text.  For
read-only access a plain IO::Scalar object is returned.  For
write-methods an internal tied class -
Krang::FTP::FileHandle::SCALAR - is used with IO::Scalar to
provide write-access to the data in the database.  Returns undef on
failure.

=cut

# Open the file handle.
sub open {
    my $self = shift;
    my $mode = shift;
    my $object = $self->{object};
    my $type = $self->{type};
    debug(__PACKAGE__."::open($mode) : ".$self->{filename}."\n");

    if ($mode eq "r") {
        # check write access
        return undef unless $self->can_read;

        # return an IO::Scalar for template content or IO::File for media on read
        if ($type eq 'template') {
            my $data = $object->content;
            return new IO::Scalar \$data;
        } else {
            my $path = $object->file_path();
            return new IO::File $path;        
        }
    } elsif ($mode eq "w") {
        # check write access
        return undef unless $self->can_write;

        return pkg('FTP::FileHandle::Handle')->new($object,$type);
        
    }
}

=item dir()

Returns the directory handle for the category that this template is
in.  Calls Bric::Util::FTP::DirHandle->new().

=cut

sub dir {
  my $self = shift;
  debug(__PACKAGE__."::dir() : ".$self->{filename}."\n");
  return pkg('FTP::DirHandle')->new (   $self->{ftps},
                                        $self->dirname,
                                        $self->{type},
                                        $self->{category_id});
}

=item status()

This method returns information about the object.  The return value is
a list with seven elements - ($mode, $perms, $nlink, $user, $group,
$size, $time).  To quote the good book (Net::FTPServer::Handle):

          $mode     Mode        'd' = directory,
                                'f' = file,
                                and others as with
                                the find(1) -type option.
          $perms    Permissions Permissions in normal octal numeric format.
          $nlink    Link count
          $user     Username    In printable format.
          $group    Group name  In printable format.
          $size     Size        File size in bytes.
          $time     Time        Time (usually mtime) in Unix time_t format.

$mode is always 'f'.  $perms is set depending on wether the template
is checked out and whether the user has access to edit the template.
$nlink is always 1.  $user is set to the user that has the template
checked out or "nobody" for checked in templates.  $group is "ci" if
the template is checked out, "ci" if it's checked in.  $size is the
size of the template text in bytes.  $time is set to the deploy_time()
of the template.

=cut

sub status {
    my $self = shift;
    my $object = $self->{object};
    my $type = $self->{type};

    debug(__PACKAGE__."::status() : ".$self->{filename}."\n");

    my ($data,$size,$date,$mode);

    if ($type eq 'template') {
        $data = $object->content;
        $size = length($data);
    } else {
        $size = $object->file_size();
    }

    $date = $object->creation_date()->epoch;
    
    my $owner = $object->checked_out_by;

    if ( $owner) { # if checked out, get the username, return read-only
        my @user = pkg('User')->find( user_id => $owner );
        my $login = defined $user[0] ? $user[0]->login : "unknown";
        return ( 'f', 0777, 1, $login, "co", $size,  $date);
    } else { # check for write privs - TODO
        my $priv = 1;
        if ($priv) {
            $mode = 0777;
        } else { 
            $mode = 0400;
        }
    return ( 'f', $mode, 1, "nobody", "ci", $size,  $date);
  }


}

=item delete()

Deletes the current media/template. This has the same effect as deleting
the object thru the UI.

=cut

sub delete {    
    my $self = shift;
    my $object = $self->{object};
    my $type = $self->{type};

    debug(__PACKAGE__."::delete() : ".$self->filename."\n");

    $object->delete;

    return 1;
}

=item can_*()

Returns permissions information for various activites.  can_read()
always returns 1 since media/templates can always be read.  can_rename() and
can_delete() return 0 since these operations are not yet supported.
can_write() and can_append() return 1 if the user can write to the
media/template - if it's checked in and the user has permission.

=cut

# fixed properties
sub can_read   {  1; }
sub can_rename {  0; }
sub can_delete {  1; }

# check to see if template is checked out
sub can_write  {
  my $self = shift;
  my @stats = $self->status();

  # this should probably be a real bit test for u+w
  if ($stats[1] == 0777) {
    return 1;
  } else {
    return 0;
  }
}
*can_append = \&can_write;

=back

=head1 SEE ALSO

Net:FTPServer::FileHandle

L<Krang::FTP::Server>

L<Krang::FTP::DirHandle>

L<Krang::FTP::FileHandle::Handle>

=cut

=cut

1;

