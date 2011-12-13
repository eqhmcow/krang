package Krang::DB;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::DB - provides access to Krang database

=head1 SYNOPSIS

  # get a database handle
  use Krang::ClassLoader DB => qw(dbh forget_dbh);
  $dbh = dbh();

  # forget about the current dbh for this instance, triggering a
  # reconnect on the next call to dbh()
  forget_dbh();

=head1 DESCRIPTION

Use this class to get a DBI handle for the active instance.  If the
database for this instance does not yet exist, it will be created.

=head1 INTERFACE

=over

=cut

use base 'Exporter';
our @EXPORT_OK = qw(dbh forget_dbh forget_all_dbhs);

use Carp qw(croak);
use DBI;

use Krang;
use Krang::ClassLoader Conf => qw(InstanceDBName DBUser DBPass DBHost DBSock KrangRoot DBIgnoreVersion);
use Krang::ClassLoader Log  => qw(info debug critical);
use Krang::ClassLoader 'Charset';

=item C<< $dbh = dbh() >>

Returns a DBI handle for the database for the active instance.  The
default options are:

  RaiseError           => 1
  AutoCommit           => 1
  mysql_auto_reconnect => 1

This call is guaranteed to return the same database handle on
subsequent calls within the same instance and process.  (Until a call
to forget_dbh(), of course.)

This method will croak() if the database to which a connection is
requested does not match the version of Krang which is currently
installed.  (This is only evaluated when a new connection is opened,
as opposed to retrieved from cache).

If you don't want the database connection to croak you have to call
dbh() with the ignore_version parameter set:

  my $dbh = dbh( ignore_version => 1 );

If you don't want to use a cached handle to the db then you can
specifically tell it:

  my $dbh = dbh(no_cache => 1);

Other parameters are passed as connection params to DBI->connect(),
overriding the default options.

=cut

our %DBH;

sub dbh {
    my %args = @_;

    my $name = InstanceDBName;
    croak(  "Unable to create dbh, InstanceDBName is undefined.\n"
          . "Maybe you forgot to call pkg('Conf')->instance()?")
      unless defined $name;

    # get args
    my $no_cache       = delete $args{no_cache};
    my $ignore_version = delete $args{ignore_version};

    # check cache
    return $DBH{$name} if !$no_cache && $DBH{$name} && $DBH{$name}->ping;

    # check for MySQL hostname
    my $dsn = "DBI:mysql:database=$name";
    $dsn .= ";host=" . DBHost if DBHost;
    $dsn .= ":mysql_read_default_group=krang";

    my %connect_options = (
        RaiseError           => 1,
        AutoCommit           => 1,
        mysql_auto_reconnect => 1,
    );

    $connect_options{mysql_socket} = DBSock if DBSock;

    my $is_utf8 = pkg('Charset')->is_utf8;
    $connect_options{mysql_enable_utf8} = 1 if $is_utf8;

    # merge in options from args
    $connect_options{$_} = $args{$_} for keys %args;

    # connect to the defined database
    $DBH{$name} = DBI->connect($dsn, DBUser, DBPass, \%connect_options);

    # Check version, unless specifically asked not to
    unless ($ignore_version || DBIgnoreVersion) {
        my ($db_version) = $DBH{$name}->selectrow_array("select db_version from db_version");
        my $krang_version = $Krang::VERSION;

        die(
            "Database <-> Krang version mismatch! (Krang v$krang_version, DB v$db_version).\n\n Unable to continue.\n"
        ) unless ($db_version == $krang_version);
    }

    return $DBH{$name};
}

=item C<< forget_dbh() >>

Causes the next call to dbh() to perform a fresh connect.  This is
useful in cases where you know the currently cached dbh() is invalid.
For example, after forking a child process a call to forget_dbh() is
necessary to avoid the parent and child trying to use the same
database connection.

=cut

sub forget_dbh () {
    my $name = InstanceDBName;
    croak(  "Unable to forget dbh, InstanceDBName is undefined.\n"
          . "Maybe you forgot to call pkg('Conf')->instance()?")
      unless defined $name;

    # delete from cache
    delete $DBH{$name};
}

=item C<< forget_all_dbhs() >>

Removes all cached DB handles. Normally C<forget_dbh()> is sufficient
but in some cases you want to forget all possible DB handles that could be cached, when
before forking when Addons and Element Libraries are in effect and could have done
their own queries.

=cut

sub forget_all_dbhs () {
    %DBH = ();
}

=back

=cut

1;
