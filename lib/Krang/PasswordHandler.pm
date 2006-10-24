package Krang::PasswordHandler;
use strict;
use warnings;
use Krang::ClassLoader Message => qw(add_message);

sub check_pw {
    my ($class, $pw, @info) = @_;

    my $valid = (length $pw >= 6);
    if( ! $valid ) {
        add_message('error_password_length');
    }
    return $valid;
}

1;

__END__

=head1 NAME

Krang::PasswordHandler - implement a system wide password policy

=head1 SYNOPSIS

  if( pkg('PasswordHandler')->check_pw(
        $pw, 
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
is created or changed, it will need to pass this module's valiation first.

It is quite likely that individual organizations will need to implement their
own password policy, which makes this an ideal class to override in an addon.

=head1 INTERFACE

=head2 check_pw

This method receives the password and return true if it passes all checks,
false otherwise. It is possible for this module to also call C<add_message()>
to indicate how the password fails the checks.

Currently, the only validation performed on a password is to make sure it
is as least 6 characters long. If it fails, then the 'error_password_length'
message is added to the message stack.

It receives the following ordered arguments

=over

=item * password

=item * user's email address

=item * user's first name

=item * user's last name

=back

If you are implementing your own password policy, it might be necessary to
check the password against this other information too.

=cut
