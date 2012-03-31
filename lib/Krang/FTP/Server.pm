package Krang::FTP::Server;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Carp qw(croak);
use Krang::ClassLoader Conf => qw(KrangUser KrangGroup);
use Krang::ClassLoader 'User';
use Krang::ClassLoader Log => qw(debug info critical reopen_log);
use Krang::ClassLoader 'FTP::FileHandle';
use Krang::ClassLoader 'FTP::DirHandle';
use Krang::ClassLoader DB => qw( forget_dbh );
use Net::FTPServer;
use Proc::Daemon;

# Inheritance
our @ISA = qw(Net::FTPServer);

=head1 NAME

Krang::FTP::Server - Virtual FTP Server for Krang Templates and Media

=head1 SYNOPSIS

    use Krang::ClassLoader 'FTP::Server';
    pkg('FTP::Server')->run();

=head1 DESCRIPTION

This module provides an FTP interface to Krang Templates and Media. The
directory tree is the site/category tree created in Krang. 
At the top level (/) will be displayed all instances in which the user 
who has logged in has a valid login/password.
Below each instance there are two directories: /template and /media. 
What appears to be directories below /template and /media 
actually correspond with L<Krang::Site>s.  Below the 
site dir appears that site's L<Krang::Category> tree as a directory 
structure. Files within these directories  
are L<Krang::Template> .tmpl files (in the /template tree),and media 
files associated with L<Krang::Media> objects (in the /media tree).
When a user downloads a .tmpl or media file 
with Krang::FTP::Server, they recieve the file from the most recent 
checked-in version of Template/Media object. When a file is uploaded it
is automatically checked in and published/deployed. 

Below is a sample directory tree as it might appear when logged in to
Krang::FTP::Server-

    /instance1/
        media/
            site1/
                test.jpg
                category1/
                    test.png
                category2/
                    test.gif
                    test2.gif
            site2/
                category1/
        template/
            site1/
                test.tmpl
                category1/
                    template2.tmpl
                category2/
            site2/
                category1/
    /instance2/
        media/
            siteA/
                whatever.jpg
                category1/
            siteB/
                category1/
                    graphic.gif
                category2/
        template/
            siteA/
                category1/
                    template.tmpl
            siteB/
                story.tmpl
                category1/
                category2/
                    lastpage.tmpl

For installation and configuration instructions see L<Krang::Admin>

=head1 LIMITATIONS

Only GET, PUT and DELETE are implemented for templates and media.  No
modification of categories is supported.

=head1 INTERFACE

This module inherits from Net::FTPServer and doesn't override any
public methods.  See L<Net::FTPServer> for details.

=head1 PRIVATE

=head2 Private Instance Methods

=over 4

=item pre_configuration_hook()

This is called by Net:FTPServer before configuration begins.  It's
used in this class to add our name and version to the version string
displayed by the server.

=cut

sub pre_configuration_hook {
    my $self = shift;

    # add to version info
    $self->{version_string} .= ' - ' . __PACKAGE__;

}

=item post_accept_hook()

This method is called by Net::FTPServer after a connection is accepted
and a child process has been forked.  It's used by this class to
change to uid/gid to KrangUser/KrangGroup.

=cut

sub post_accept_hook {
    reopen_log();

    # get current uid/gid
    my $uid = $>;
    my %gid = map { ($_ => 1) } split(' ', $));

    # extract desired uid/gid
    my @uid_data = getpwnam(KrangUser);
    croak("Unable to find user for KrangUser '" . KrangUser . "'.")
      unless @uid_data;
    my $krang_uid = $uid_data[2];
    my @gid_data  = getgrnam(KrangGroup);
    croak("Unable to find user for KrangGroup '" . KrangGroup . "'.")
      unless @gid_data;
    my $krang_gid = $gid_data[2];

    # become KrangUser/KrangGroup if necessary
    if ($gid{$krang_gid}) {
        eval { $) = $krang_gid; };
        die(    "Unable to become KrangGroup '"
              . KrangGroup
              . "' : $@\n"
              . "Maybe you need to start this process as root.\n")
          if $@;
        die(    "Failed to become KrangGroup '"
              . KrangGroup
              . "' : $!.\n"
              . "Maybe you need to start this process as root.\n")
          unless $) == $krang_gid;
    }

    if ($uid != $krang_uid) {
        eval { $> = $krang_uid; };
        die(    "Unable to become KrangUser '"
              . KrangUser
              . "' : $@\n"
              . "Maybe you need to start this process as root.\n")
          if $@;
        die(    "Failed to become KrangUser '"
              . KrangUser
              . "' : $!\n"
              . "Maybe you need to start this process as root.\n")
          unless $> == $krang_uid;
    }
}

=item transfer_hook($mode, $file, $sock, \$buffer);

  $mode     -  Open mode on the File object (Either reading or writing)
  $file     -  File object as returned from DirHandle::open
  $sock     -  Data IO::Socket object used for transfering
  \$buffer  -  Reference to current buffer about to be written

The \$buffer is passed by reference to minimize the stack overhead
for efficiency purposes only.  It is B<not> meant to be modified by
the transfer_hook subroutine.  (It can cause corruption if the
length of $buffer is modified.)

Hook: This hook is called after reading $buffer and before writing
$buffer to its destination.  If arg1 is "r", $buffer was read
from the File object and written to the Data socket.  If arg1 is
"w", $buffer will be written to the File object because it was
read from the Data Socket.  The return value is the error for not
being able to perform the write.  Return undef to avoid aborting
the transfer process.

Status: optional.

=cut

sub transfer_hook {
    my $self         = shift;
    my $mode         = shift;
    my $file         = shift;
    my $sock         = shift;
    my $buffer_ref   = shift;

    # prevent "Wide character in syswrite" error when downloading template with utf8 characters.
    if (ref($file) && $file->isa('IO::Scalar') && $mode eq 'r') {
        binmode($sock, ":utf8")
    }

    return undef;
}

=item authenticaton_hook($user, $pass, $user_is_anon)

When a user logs in authentication_hook() is called to check their
username and password.  This method calls
Krang::User->find() using the given username and then
checks the password.  Also stores the Krang::User object into
$self->{user_obj}. Returns -1 on login failure or 0 on success.

=cut

sub authentication_hook {
    my $self         = shift;
    my $user         = shift;
    my $pass         = shift;
    my $user_is_anon = shift;
    my @auth_instances;
    my %user_objects;
    my $login_found;

    # log this attempt to login
    info(__PACKAGE__ . " Login attempt- Username:$user.");

    # disallow anonymous access.
    return -1 if $user_is_anon;

    # check each instance to see if user has login on each
    foreach my $instance (pkg('Conf')->instances()) {

        # set instance
        pkg('Conf')->instance($instance);

        # get user object
        my @user_object = pkg('User')->find(login => $user);

        next if not $user_object[0];

        $user_objects{$instance} = $user_object[0];

        debug(__PACKAGE__ . " User object found for login $user in instance $instance.");

        # return failure if authentication fails.
        my $login_ok = pkg('User')->check_auth($user, $pass);

        if ($login_ok) {
            push @auth_instances, $instance;
            $login_found = 1;
        }
    }

    if (not $login_found) {
        info(__PACKAGE__ . " login/password denied for user $user.");
        return -1;
    }

    # undefine instance until they choose one at top level
    pkg('Conf')->instance(undef);

    # set accepted instances
    $self->{auth_instances} = \@auth_instances;
    $self->{user_objects}   = \%user_objects;

    # successful login.
    info(__PACKAGE__ . " login/password accepted for user $user, instances: @auth_instances.");

    return 0;
}

=item root_directory_hook()

Net::FTPServer calls this method to get a DirHandle for the root
directory.  This method just calls Krang::FTP::DirHandle->new().

=cut

sub root_directory_hook {
    my $self = shift;
    return pkg('FTP::DirHandle')->new($self);
}

=item system_error_hook()

This method is called when an error is signaled elsewhere in the
server.  It looks for a key called "error" in $self and returns that
if it's available.  This allows for an OO version of the ever-popular
$! mechanism.  (Or, at least, that's the idea.  As far as I can tell
it never really gets called!)

=cut

sub system_error_hook {
    my $self = shift;
    return delete $self->{error}
      if exists $self->{error};
    return "Unknown error occurred.";
}

# override Net::FTPServer's forking sub so that we properly close
# our IO handles to the terminal. Not sure why Net::FTPServer doesn't
# do this because it does try. But Proc::Daemon does a better job and
# actually gets it right
sub _fork_into_background {
    my $self = shift;
    Proc::Daemon::Init();
}


1;

=back

=cut

1;
