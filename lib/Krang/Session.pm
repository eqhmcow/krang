package Krang::Session;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader DB  => qw(dbh);
use Krang::ClassLoader Log => qw(critical);
use Krang::ClassLoader 'MyPref';
use Apache::Session::Flex;
use Carp qw(croak);
use Storable qw/nfreeze thaw/;

=head1 NAME

Krang::Session - session handling for Krang

=head1 SYNOPSIS

  use Krang::ClassLoader Session => qw(%session);

  # get some session data
  my $bang = $session{buck};

  # get the session id
  my $session_id = $session{_session_id};

  # set from session data
  $session{buck} = $bang + 1;

  # delete from the session hash
  delete $session{buck};

  # it's that simple

=head1 DESCRIPTION

This module provides access to a peristent hash per user session.
This is available both in Apache/mod_perl, where a user session lasts
from login to logout, and from shell scripts, where a user session
lasts from process start to process end.

The session hash should be used for data that must persist between
requests but is not permanent enough to be stored in the database.
The most obvious usage is to maintain state while editing an object
before eventually saving changes to the database.

B<NOTE> The session hash should not be used as a general mechanism to
speed up Krang.  This is not a cache, it is an intermediary data
store.

Sessions older than 24 hours are cleaned out daily by the scheduler.
See Krang::Schedule::Action::clean for details.

=head1 INTERFACE

Aside from the exported %session hash, the module supports the
following routines.

=cut

our %session;
our $tied = 0;
require Exporter;
our @ISA       = ('Exporter');
our @EXPORT_OK = ('%session');

=over 4

=item C<< $session_id = Krang::Session->create() >>

Create a new session and return the session id, to be used in a later
call to C<load()>.  After this call, C<%session> is attached to the
new session.

=cut

sub create {
    my $pkg = shift;
    my $dbh = dbh();
    tie %session, 'Apache::Session::Flex', undef,
      {
        Store      => 'MySQL',
        Generate   => 'MD5',
        Serialize  => 'Storable',
        Handle     => $dbh,
        Lock       => 'MySQL',
        LockHandle => $dbh,
      }
      or croak("Unable to create new session.");
    $tied = 1;

    my $session_id = $session{_session_id};
    croak("Unable to create new session, null session_id")
      unless defined $session_id;
    return $session_id;
}

=item C<< Krang::Session->load($session_id) >>

Loads a session by id.  After this call, C<%session> is attached to
the specified session.  If the session cannot be found, this routine
will croak().

=cut

sub load {
    my $pkg        = shift;
    my $session_id = shift;
    my $dbh        = dbh();

    # check if the session even exists
    my ($exists) = $dbh->selectrow_array('SELECT 1 FROM sessions WHERE id = ?', undef, $session_id);
    croak("Session '$session_id' does not exist!")
      unless $exists;

    # try to tie the session
    eval {
        tie %session, 'Apache::Session::Flex', $session_id,
          {
            Store      => 'MySQL',
            Generate   => 'MD5',
            Serialize  => 'Storable',
            Handle     => $dbh,
            Lock       => 'MySQL',
            LockHandle => $dbh,
          }
          or croak("Unable to create new session.");
        $tied = 1;
    };

    # delete session if it failed to load, which will prevent a broken
    # session from totally breaking the application
    if (my $err = $@) {
        $dbh->do('DELETE FROM sessions WHERE id = ?', undef, $session_id);
        croak("Unable to load session '$session_id': $err");
    }

    # touch a key to make sure it gets saved on unload,
    # Apache::Session will miss a change several levels down unless a
    # top-level value changes.
    $session{__load_count__}++;
}

=item C<< $is_valid = Krang::Session->validate($session_id) >>

Validates a session by id, without loading it.  Returns 1 if the
session is valid and 0 if not.

=cut

sub validate {
    my $pkg        = shift;
    my $session_id = shift;
    my $dbh        = dbh();

    my ($exists) = $dbh->selectrow_array('SELECT 1 from sessions where id = ?', undef, $session_id);

    return $exists ? 1 : 0;
}

=item C<< Krang::Session->unload() >>

Unloads the current session, saving modified state to disk.  If this
routine is not called then the session will be saved the next time a
session is loaded or when the process ends.

After this call, C<%session> will be unavailable until the next call to
C<load()>.

=cut

sub unload {
    $_[0]->persist_to_mypref();
    untie %session if $tied;
    $tied = 0;
}

=item C<< Krang::Session->delete() >>

=item C<< Krang::Session->delete($session_id) >>

Deletes a session from the store, permanently.  A session id can be
specified, or the current session will be deleted.

=back

=cut

sub delete {
    my $pkg        = shift;
    my $session_id = shift;
    my $dbh        = dbh();

    if ($session_id) {
        tie my %doomed, 'Apache::Session::Flex', $session_id,
          {
            Store      => 'MySQL',
            Generate   => 'MD5',
            Serialize  => 'Storable',
            Handle     => $dbh,
            Lock       => 'MySQL',
            LockHandle => $dbh,
          }
          or croak("Unable to create new session.");
        tied(%doomed)->delete();
        untie(%doomed);
    } elsif ($tied) {
        tied(%session)->delete();
        untie(%session);
        $tied = 0;
    }
}

sub persist_to_mypref {
    my $self = shift;

    # session's persistent part
    my $persist = $session{KRANG_PERSIST};

    pkg('MyPref')->set(config => nfreeze($persist)) if $persist;
}

1;

