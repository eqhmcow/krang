package Krang::DB;
use strict;
use warnings;

=head1 NAME

Krang::DB - provides access to Krang database

=head1 SYNOPSIS

  # get a database handle
  use Krang::DB qw(dbh);
  $dbh = dbh();

=head1 DESCRIPTION

Use this class to get a DBI handle for the active instance.

=head1 INTERFACE

=over

=item C<< $dbh = dbh() >>

Returns a DBI handle for the database for the active instance.  The
default options are:

  RaiseError         => 1
  AutoCommit         => 1
  ShowErrorStatement => 1

=back

=cut

use DBI;
use base 'Exporter';
our @EXPORT_OK = qw(dbh);

use Krang::Conf qw(DBName DBUser DBPass);
use Carp qw(croak);

our %DBH;

sub dbh () {
    my $name = DBName();
    croak("Unable to create dbh, DBName is undefined.\n" . 
          "Maybe you forgot to call Krang::Conf->instance()?")
      unless defined $name;

    return $DBH{$name} if exists $DBH{$name};
    $DBH{$name} = DBI->connect("DBI:mysql:database=$name", DBUser(), DBPass(),
                               { RaiseError         => 1, 
                                 AutoCommit         => 1,
                                 ShowErrorStatement => 1,
                               });
    return $DBH{$name};
}

=head1 TODO

Should use Apache::DBI if running in mod_perl.

=cut

1;
