package Krang;
use strict;
use warnings;

our $VERSION = "0.001";

=head1 NAME

Krang - loader for the Krang system

=head1 SYNOPSIS

  use Krang;

=head1 DESCRIPTION

This module exists only to load and configure other modules.  All
Krang clients should load this module first before using other Krang
modules.

When loaded from outside Apache/mod_perl, this module will activate
the first instance defined in F<krang.conf> by calling:

  Krang::Conf->instance((Krang::Conf->instances())[0]);

You can override this behavior by setting the KRANG_INSTANCE
environment variable.

When loaded from Apache/mod_perl no default instance is set since
Krang::Handler will set the instance at the start of each request
depending on the vhost accessed.

=head1 INTERFACE

None.

=head1 TODO

The way the session setup for non-Apache usage gets user_id 1 with no
authentication is mighty hinky.

=cut

use Carp qw(verbose croak); # turn croaks into confesses

# load base Krang modules
use Krang::Conf qw(ElementSet);
use Krang::Log qw(critical info debug);
use Krang::ElementLibrary;
use Krang::Session qw(%session);

# load all configured element sets
BEGIN {
    foreach my $instance (Krang::Conf->instances()) {
        Krang::Conf->instance($instance);
        Krang::ElementLibrary->load_set(set => ElementSet());
    }
    Krang::Conf->instance(undef);
}        


BEGIN {
    # get ready to handle CGI requests if running under Apache/mod_perl.
    if ($ENV{MOD_PERL}) {
        # load interface modules
        use Krang::CGI;
        use Krang::Handler;

    # otherwise, setup the instance and session stuff which
    # Krang::Handler handles for Apache
    } else {
        # setup default instance if not running under mod_perl or inside a CGI
        my $instance = exists $ENV{KRANG_INSTANCE} ? 
          $ENV{KRANG_INSTANCE} : (Krang::Conf->instances())[0];
        debug "Setting instance to '$instance'";
        Krang::Conf->instance($instance);


        # open up a session
        my $session_id = Krang::Session->create();

        # get a user_id from KRANG_USER_ID or default to 1
        my $user_id = exists $ENV{KRANG_USER_ID} ? $ENV{KRANG_USER_ID} : 1;
        $session{user_id} = $user_id;
        debug "Setting user_id to $user_id";

        # arrange for it to be deleted at process end
        eval "END { Krang::Session->delete() }";
    }
}

# setup die handler to write fatal errors to the log before really
# dying.  In Apache/mod_perl, this is done with an eval {} in
# Krang::Handler.
unless ($ENV{MOD_PERL}) {
    $SIG{__DIE__} = sub {
        return if $^S;   # ignore die inside an eval
        critical $_[0];
        die $_[0];
    };
}

info("Krang v$VERSION loaded");

1;
