package Krang::Pref;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Carp qw(croak);
use Krang::ClassLoader DB => qw(dbh);

=head1 NAME

Krang::Pref - Krang Global Preference API

=head1 SYNOPSIS

  use Krang::ClassLoader 'Pref';

  # get the value set 'search_page_size', a scalar preference
  $page_size = pkg('Pref')->get('search_page_size');

  # get a hash of ids to names for a list preference
  %data = pkg('Pref')->get('contrib_type');

  # set a scalar preference
  pkg('Pref')->set(search_page_size => 10);

  # set a list preference with a list of ids and names
  pkg('Pref')->set(contrib_type => 1 => 'Writer', 2 => 'Photographer');

=head1 DESCRIPTION

Krang::Pref provides a means for the user to access and change
configurable settings.

There are two types of Preferences: scalars and lists.  A scalar
preference accepts a single value.  A list preference contains a list
of values, identified by unique IDs mapping to names.

The following preferenes are supported by Krang::Pref:

=over 4

=item contrib_type (list)

List of contributor types, used by Krang::Contrib.

=item media_type (list)

List of media types, used by Krang::Media.

=item search_page_size (scalar)

Default search page size, used by Krang::UserPref as a default.

=back

=cut

our %CONFIG = (
    contrib_type => {
        type       => 'list',
        table      => 'contrib_type',
        id_field   => 'contrib_type_id',
        name_field => 'type',
    },
    media_type => {
        type       => 'list',
        table      => 'media_type',
        id_field   => 'media_type_id',
        name_field => 'name',
    },
    search_page_size => {
        type => 'scalar',
        row  => 'search_page_size',
    },
    use_autocomplete => {
        type => 'scalar',
        row  => 'use_autocomplete',
    },
    message_timeout => {
        type => 'scalar',
        row  => 'message_timeout',
    },
);

=pod

New preferences can be added by editing the configuration data in this
module.

=head1 INTERFACE

=over 4

=item C<< $opt_id = Krang::Pref->add_option($list_pref_name, $new_pref_opt) >>

Adds a new option to the list of available options for a list preference.  The
id of the new option is returned.

=cut

sub add_option {
    my ($pkg, $pref, $opt) = @_;
    my $conf = $CONFIG{$pref};
    my $dbh  = dbh();

    croak("Invalid pref '$pref' does not exist in %Krang::Pref::CONFIG")
      unless $conf;
    croak("Pref '$pref' must be of type 'list'.")
      unless $conf->{type} eq 'list';

    my $sql = "INSERT INTO $conf->{table} ($conf->{name_field}) VALUES (?)";
    $dbh->do($sql, undef, $opt);

    $sql = "SELECT $conf->{id_field} FROM $conf->{table} WHERE " .
      "$conf->{name_field} = ?";
    my $row = $dbh->selectrow_arrayref($sql, undef, $opt);

    return $row->[0];
}



=item $value = Krang::Pref->get('scalar_pref');

=item %hash = Krang::Pref->get('list_pref');

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
    croak("Invalid pref '$name' does not exist in %Krang::Pref::CONFIG")
      unless $conf;

    if ($conf->{type} eq 'scalar') {
        # handle scalar pref
        my ($value) = $dbh->selectrow_array(
                              'SELECT value FROM pref WHERE id = ?',
                                            undef, $conf->{row});
        return $value;
    } elsif ($conf->{type} eq 'list') {
        # handle list pref
        my $result = $dbh->selectall_arrayref(
                              "SELECT $conf->{id_field}, $conf->{name_field}
                               FROM   $conf->{table}");
        return unless $result and @$result;
        return map { @$_ } @$result;
    }
    
    croak("Unknown pref type '$conf->{type}'");    
}

=item Krang::Pref->set(scalar_pref => 'value');

=item Krang::Pref->set(list_pref => 1 => "value1", 2 => "value2");

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
    croak("Invalid pref '$name' does not exist in %Krang::Pref::CONFIG")
      unless $conf;

    if ($conf->{type} eq 'scalar') {
        $dbh->do('REPLACE INTO pref (id, value) VALUES (?,?)', undef, 
                 $conf->{row}, $args[0]);
    } elsif ($conf->{type} eq 'list') {
        $dbh->do("DELETE FROM $conf->{table}");
        while(@args) {
            my $id = shift @args;
            my $name = shift @args;
            $dbh->do("INSERT INTO $conf->{table} 
                        ($conf->{id_field}, $conf->{name_field})
                      VALUES (?, ?)", undef, $id, $name);
        }
    } else {
        croak("Unknown pref type '$conf->{type}'");
    }
}

1;

=back
