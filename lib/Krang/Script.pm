package Krang::Script;
use strict;
use warnings;

=head1 NAME

Krang - loader for the Krang scripts

=head1 SYNOPSIS
 
  use Krang::Script;

=head1 DESCRIPTION

This module exists to load and configure the Krang system for
command-line scripts.

This module will activate the first instance defined in F<krang.conf>
by calling:

  Krang::Conf->instance((Krang::Conf->instances())[0]);

You can override this behavior by setting the KRANG_INSTANCE
environment variable.

=head1 INTERFACE

None.

=head1 TODO

The way the session setup gets user_id 1 with no authentication is
mighty hinky.  Fix it to use KRANG_USERNAME and KRANG_PASSWORD.

=cut

use Krang::Conf;
use Krang::Log qw(debug critical);
use Krang::Session qw(%session);

BEGIN {
    # Set Krang instance if not running under mod_perl
    my $instance = exists $ENV{KRANG_INSTANCE} ? 
      $ENV{KRANG_INSTANCE} : (Krang::Conf->instances())[0];
    debug("Krang.pm:  Setting instance to '$instance'");    
    Krang::Conf->instance($instance);
    
    my $session_id = Krang::Session->create();
    
    # get a user_id from KRANG_USER_ID or default to 1
    my $user_id = exists $ENV{KRANG_USER_ID} ? $ENV{KRANG_USER_ID} : 1;
    $session{user_id} = $user_id;
    debug "Setting user_id to $user_id";

    $SIG{__DIE__} = sub {
        return if $^S;   # ignore die inside an eval
        my $err = shift;
        critical $err;
        die $err;
    };
}

# arrange for session to be deleted at process end
END { 
    Krang::Session->delete();
}

1;
