package Krang::Upgrade;
use Krang::ClassFactory qw(pkg);
use warnings;
use strict;

use Krang::ClassLoader 'Conf';
use Krang::ClassLoader DB => qw(dbh);
use Krang::ClassLoader 'AddOn';
#use Krang::ClassLoader 'Script';
use Carp qw(croak);
use File::Spec::Functions qw(catfile);

# call the init-handler of any AddOns being used
BEGIN {
    pkg('AddOn')->call_handler('InitHandler');
}

=head1 NAME

Krang::Upgrade - superclass for Krang upgrade modules


=head1 SYNOPSIS

  use Krang::ClassLoader base => 'Upgrade';


=head1 DESCRIPTION

This module is intended to be used as a parent class for Krang upgrade
modules.  It implements a harness for calling the C<per_installation()> 
and C<per_instance()> methods.


=head1 INTERFACE

To use this module, there are three things you have to do:


=over 4

=item use Krang::ClassLoader base => 'Upgrade';

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

The following named parameters may be passed which will then get passed
along to C<per_installation()> and C<per_instance()>.

=over

=item * no_db

This tells the upgrade module that the upgrade should not make changes to
the database.

=back

=item remove_files()

This convenience method is provided to help remove old files during
the upgrade.  It's best to call this method in the
C<per_installation()> method since files are per-installation. File
names are given relative to C<KRANG_ROOT>. If a directory name is
passed to this method, the directory and all its content will be
deleted recursively.

    $self->remove_files(
        'lib/Krang/Foo.pm',
        'src/Foo-1.00.tar.gz',
    );

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

sub remove_files {
    my ($self, @files) = @_;
    foreach my $file (@files) {
        $file = catfile($ENV{KRANG_ROOT}, $file);
        system("rm -rf $file") if (-e $file || -d $file);
    }
}

# Create a trivial object
sub new {
    my $class = shift;
    bless({}, $class);
}

sub upgrade {
    my ($self, %args) = @_;

    # Run per_installation() method
    $self->per_installation(%args);

    # Run per_instance() method, for each instance
    my @instances = pkg('Conf')->instances();
    foreach my $instance (@instances) {

        # Switch to that instance
        pkg('Conf')->instance($instance);

        # Load the dbh, without version checking, to prime cache
        my $dbh = dbh(ignore_version => 1);

        # Call per_instance(), now that the environment has been established
        $self->per_instance(%args);
    }
}

1;
