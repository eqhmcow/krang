package Krang::Upgrade;
use Krang::ClassFactory qw(pkg);
use warnings;
use strict;


use Krang::ClassLoader 'Conf';
use Krang::ClassLoader DB => qw(dbh);
use Carp qw(croak);


=head1 NAME

Krang::Upgrade - superclass for Krang upgrade modules


=head1 SYNOPSIS

  use base 'Krang::Upgrade';


=head1 DESCRIPTION

This module is intended to be used as a parent class for Krang upgrade
modules.  It implements a harness for calling the C<per_installation()> 
and C<per_instance()> methods.


=head1 INTERFACE

To use this module, there are three things you have to do:


=over 4

=item use base 'Krang::Upgrade';

This causes your upgrade module (e.g., "V1_23.pm") to inherit
certain basic functionality.  Specifically, an C<upgrade()>
method which calls C<per_installation()>, and then calls
C<per_instance()> once for each instance.


=item per_installation()

You must implement this method in your upgrade module.  This method
is called once per upgrade, before the C<per_instance()> method is called.

This method is called (as an object method) by the inherited upgrade() method.


=item per_instance()

You must implement this method in your upgrade module.  This method
is called once per Krang instance, after the C<per_installation()> 
method is called.

This method is called (as an object method) by the inherited upgrade() method.

=back


=head2 INHERITED METHODS

=over 4


=item new()

The new() method is a constructor which creates a trivial object from a
hash.  Your upgrade modules may use this to store state information.


=item upgrade()

The upgrade() method is called by the krang_upgrade script to implement
an upgrade.  This method calls C<per_installation()>, and then calls 
C<per_instance()> once for each installed instance.


=back


=head1 SEE ALSO

Releasing Krang: Creating Upgrade Modules  F<docs/release.pod>



=cut


sub per_installation {
    my $self = shift;
    croak("No per_installation() method implemented in $self");
}


sub per_instance {
    my $self = shift;
    croak("No per_instance() method implemented in $self");
}


# Create a trivial object
sub new {
    my $class = shift;
    bless({}, $class);
}


sub upgrade {
    my $self = shift;

    # Run per_installation() method
    $self->per_installation();

    # Run per_instance() method, for each instance
    my @instances = pkg('Conf')->instances();
    foreach my $instance (@instances) {
        # Switch to that instance
        pkg('Conf')->instance($instance);

        # Load the dbh, without version checking, to prime cache
        my $dbh = dbh(ignore_version=>1);

        # Call per_instance(), now that the environment has been established
        $self->per_instance();
    }
}




1;
