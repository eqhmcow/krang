package Krang::DB;
use strict;
use warnings;

=head1 NAME

Krang::DB - provides access to Krang database

=head1 SYNOPSIS

  # get a database handle
  use Krang::DB qw(dbh forget_dbh);
  $dbh = dbh();

  # forget about the current dbh for this instance, triggering a
  # reconnect on the next call to dbh()
  forget_dbh();

=head1 DESCRIPTION

Use this class to get a DBI handle for the active instance.  If the
database for this instance does not yet exist, it will be created.

=head1 INTERFACE

=over

=item C<< $dbh = dbh() >>

Returns a DBI handle for the database for the active instance.  The
default options are:

  RaiseError         => 1
  AutoCommit         => 1

This call is guaranteed to return the same database handle on
subsequent calls within the same instance and process.  (Until a call
to forget_dbh(), of course.)

=item C<< forget_dbh() >>

Causes the next call to dbh() to perform a fresh connect.  This is
useful in cases where you know the currently cached dbh() is invalid.
For example, after forking a child process a call to forget_dbh() is
necessary to avoid the parent and child trying to use the same
database connection.

=back

=cut

use DBI;
use base 'Exporter';
our @EXPORT_OK = qw(dbh forget_dbh);

use Krang::Conf qw(InstanceDBName DBUser DBPass KrangRoot);
use Carp qw(croak);

use Krang::Log qw(info debug critical);


our %DBH;

sub dbh () {
    my $name = InstanceDBName;
    croak("Unable to create dbh, InstanceDBName is undefined.\n" . 
          "Maybe you forgot to call Krang::Conf->instance()?")
      unless defined $name;

    # check cache
    return $DBH{$name} if $DBH{$name} and $DBH{$name}->ping;

    # connect to the defined database
    $DBH{$name} = DBI->connect("DBI:mysql:database=$name", DBUser, DBPass,
                               { RaiseError         => 1, 
                                 AutoCommit         => 1,
                               });
    return $DBH{$name};
}

sub forget_dbh () {
    my $name = InstanceDBName;
    croak("Unable to forget dbh, InstanceDBName is undefined.\n" . 
          "Maybe you forgot to call Krang::Conf->instance()?")
      unless defined $name;

    # delete from cache
    delete $DBH{$name};
}

=head1 TODO

Should use Apache::DBI if running in mod_perl.

=cut

1;
