package Krang::MyPref;
use strict;
use warnings;

use Carp qw(croak);
use Krang::DB qw(dbh);
use Krang::Session qw(%session);

=head1 NAME

Krang::MyPref - Krang user preference API

=head1 SYNOPSIS

  use Krang::MyPref;

  # get the value set 'search_page_size', a scalar preference
  $page_size = Krang::MyPref->get('search_page_size');

  # set a scalar preference
  Krang::MyPref->set(search_page_size => 10);

=head1 DESCRIPTION

Krang::MyPref provides a means for the user to access and change
configurable settings.

There are two types of Preferences: scalars and lists.  A scalar
preference accepts a single value.  A list preference contains a list
of values, identified by unique IDs mapping to names.

The following preferenes are currently supported by Krang::MyPref:

=over 4

=item search_page_size (scalar)

Default search page size.

=back

=cut

our %CONFIG = 
  (
   search_page_size => {
                        type  => 'scalar',
                        row   => 'search_page_size',
                       },
);

=pod

New preferences can be added by editing the configuration data in this
module.

=head1 INTERFACE

=over 4

=item $value = Krang::MyPref->get('scalar_pref');

=item %hash = Krang::MyPref->get('list_pref');

Gets the data configured for a given preference.  For scalar
preferences, returns the configured value.  For list preferences,
returns a hash mapping IDs to names.

If no value has been configured for the preference then nothing is
returned (undef in scalar context, empty list in list context).

=cut

sub get {
    my ($pkg, $name) = @_;
    my $conf = $CONFIG{$name};
    my $dbh  = dbh();
    croak("Invalid pref '$name' does not exist in %Krang::MyPref::CONFIG")
      unless $conf;
    my $user_id = $session{user_id};

    if ($conf->{type} eq 'scalar') {
        # handle scalar pref
        my ($value) = $dbh->selectrow_array(
                              'SELECT value FROM my_pref WHERE id = ? and user_id = ?',
                                            undef, $conf->{row}, $user_id);
        return $value;
    } elsif ($conf->{type} eq 'list') {
        # handle list pref
        my $result = $dbh->selectall_arrayref(
                              "SELECT $conf->{id_field}, $conf->{name_field}
                               FROM   $conf->{table} where user_id = ?", undef, $user_id);
        return unless $result and @$result;
        return map { @$_ } @$result;
    }
    
    croak("Unknown my_pref type '$conf->{type}'");    
}

=item Krang::MyPref->set(scalar_pref => 'value');

=item Krang::MyPref->set(list_pref => 1 => "value1", 2 => "value2");

Sets a preference to a given value.  For scalar preferences, takes a
single value.  For list preferences, takes a list a IDs and
corresponding names.

Note that this method does not do any dependency checking on values
being removed from the table.

=cut

sub set {
    my ($pkg, $name, @args) = @_;
    my $conf = $CONFIG{$name};
    my $dbh  = dbh();
    my $user_id = $session{user_id};
    croak("Invalid pref '$name' does not exist in %Krang::MyPref::CONFIG")
      unless $conf;

    if ($conf->{type} eq 'scalar') {
        $dbh->do('REPLACE INTO my_pref (id, value, user_id) VALUES (?,?,?)', undef, 
                 $conf->{row}, $args[0], $user_id);
    } elsif ($conf->{type} eq 'list') {
        $dbh->do("DELETE FROM $conf->{table}");
        while(@args) {
            my $id = shift @args;
            my $name = shift @args;
            $dbh->do("INSERT INTO $conf->{table} 
                        ($conf->{id_field}, $conf->{name_field}, user_id)
                      VALUES (?, ?, ?)", undef, $id, $name, $user_id);
        }
    } else {
        croak("Unknown my_pref type '$conf->{type}'");
    }
}

1;

=back
