package Krang::PasswordHandler;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader Message => qw(add_alert);
use Krang::ClassLoader DB => qw(dbh);
use Krang::ClassLoader 'User';
use Digest::MD5 qw(md5_hex);

use Krang::User;
my $SALT = $Krang::User::SALT;

sub check_pw {
    my ($class, $pw, @info) = @_;

    my $valid = 0;
    if( length $pw < 6 ) {
        add_alert('password_too_short');
    } elsif( _pw_is_used($pw, $info[0]) ) {
        add_alert('password_currently_used');
    } elsif( _pw_was_used($pw, $info[0]) ) {
        add_alert('password_used_recently');
    } else {
        $valid = 1;
    }
    return $valid;
}

# check if this is our current password
sub _pw_is_used {
    my ($pw, $login) = @_;

    # look for a user with that login
    my ($user) = pkg('User')->find(login => $login);
    if( $user ) {
        return (md5_hex($SALT, $pw) eq $user->password);
    }
    return 0;
}

# check if this is a password we have used recently
sub _pw_was_used {
    my ($pw, $login) = @_;
    my $bad = 0;

    # look for a user with that login
    my ($user) = pkg('User')->find(login => $login);
    if( $user ) {
        # see if they have an MD5 of this pw in the old_password table
        my $sth = dbh()->prepare_cached(
            'SELECT password FROM old_password WHERE user_id = ?'
        );
        $sth->execute($user->user_id);
        my $old_pws = $sth->fetchall_arrayref();
        foreach my $row (@$old_pws) {
            return 1 if(md5_hex($SALT, $pw) eq $row->[0]);
        }
    }
    # else it wasn't found so we're in the clear
    return 0;
}

1;

__END__

=head1 NAME

Krang::PasswordHandler - implement a system wide password policy

=head1 SYNOPSIS

  if( pkg('PasswordHandler')->check_pw(
        $pw, 
        $user->login,
        $user->email,
        $user->first_name,
        $user->last_name,
    ) ) {
    # it's good to go
  } else {
    # tell the user to pick something else
  }

=head1 DESCRIPTION

This module implements the password policy for Krang. Anywhere a password
is created or changed, it will need to pass this module's validation first.

It is quite likely that individual organizations will need to implement their
own password policy, which makes this an ideal class to override in an addon.

=head1 INTERFACE

=head2 check_pw

This method receives the password and returns true if it passes all checks,
false otherwise. It is possible for this module to also call C<add_alert()>
to indicate how the password fails the checks.

It receives the following ordered arguments

=over

=item * password

=item * user's login

=item * user's email address

=item * user's first name

=item * user's last name

=back

If you are implementing your own password policy, it might be necessary to
check the password against this other information too.

Currently, the following validation rules are applied:

=over

=item * the password must be least 6 characters long. 

If it fails, then the 'password_too_short' message is added to the message stack.

=item * the password must not be the user's current password

If it fails, then the 'password_currently_used' message is added to the message stack.

=item * the password must not be in the C<old_password> table for this user.

How many passwords are stored in the C<old_password> is configured by the
C<PasswordChangeCount> configuration variable.

If it fails, then the 'password_used_recently' message is added to the message stack.

=cut
