package Krang::DB;
use strict;
use warnings;

=head1 NAME

Krang::DB - provides access to Krang database

=head1 SYNOPSIS

  # get a database handle
  use Krang::DB qw(dbh create_db forget_dbh);
  $dbh = dbh();

  # create an empty database for an instance
  create_db($instance);

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

If the database for the current instance does not exist, will call
create_db() automatically.

This call is guaranteed to return the same database handle on
subsequent calls within the same instance and process.  (Until a call
to forget_dbh(), of course.)

=item C<< create_db() >>

Creates an empty Krang database for the current instance.  Will drop
the database for this instance, if one exists, so be careful with this
call.  Called automatically from dbh() if no database exists.

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
our @EXPORT_OK = qw(dbh create_db forget_dbh);

use Krang::Conf qw(DBName DBUser DBPass KrangRoot);
use List::Util qw(first);
use Carp qw(croak);
use File::Find qw(find);
use IPC::Run qw(run);
use File::Spec::Functions qw(catdir);

use Krang::Log qw(info debug critical);


our %DBH;

sub dbh () {
    my $name = DBName;
    croak("Unable to create dbh, DBName is undefined.\n" . 
          "Maybe you forgot to call Krang::Conf->instance()?")
      unless defined $name;

    # check cache
    return $DBH{$name} if $DBH{$name} and $DBH{$name}->ping;

    # does this db exist?  create if not
    # create_db() 
    #  unless first { "DBI:mysql:$name" eq $_ }  DBI->data_sources("mysql");
    
    $DBH{$name} = DBI->connect("DBI:mysql:database=$name", DBUser, DBPass,
                               { RaiseError         => 1, 
                                 AutoCommit         => 1,
                               });
    return $DBH{$name};
}

sub forget_dbh () {
    my $name = DBName;
    croak("Unable to create dbh, DBName is undefined.\n" . 
          "Maybe you forgot to call Krang::Conf->instance()?")
      unless defined $name;

    # check cache
    delete $DBH{$name};
}

# create the database
sub create_db {
    my $name = DBName;
    my $dbh =  DBI->connect("DBI:mysql:database=mysql", DBUser, DBPass,
                            { RaiseError         => 1, 
                              AutoCommit         => 1,
                              ShowErrorStatement => 1,
                            });
    $dbh->do("DROP DATABASE IF EXISTS $name");
    $dbh->do("CREATE DATABASE $name");
    critical("Created '$name' database.");

    # call load_sql for all sql scripts
    find(\&load_sql, catdir(KrangRoot, "sql"));    
}

# load SQL files using mysql command-line client
sub load_sql {
    return unless /\.sql$/;
    my $sql = $_;

    my @command =  ('mysql', '-u', DBUser, 
                    (length(DBPass) ? ('-p', DBPass) : ()),
                    DBName);
    my $fh = IO::File->new("<$sql");
    
    run \@command, $fh, 
      sub { debug("Loading 'sql/$sql': " . shift) }, 
        sub { croak("Error loading 'sql/$sql': " . shift) }
          or croak "Unable to load 'sql/$sql': $?";
}

=head1 TODO

Should use Apache::DBI if running in mod_perl.

=cut

1;
