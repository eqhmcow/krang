package Krang::CGI::Login;
use strict;
use warnings;

=head1 NAME

Krang::CGI::Login - web login to Krang instance

=head1 SYNOPSIS

  http://krang/instance_name/login

=head1 DESCRIPTION

Krang login CGI.  Handles user login and passes out cookies.  See
L<Krang::Handler::auth_handler> for the other end of the process.

=head1 INTERFACE

None.

=cut


use base 'Krang::CGI';
use Digest::MD5 qw(md5_hex md5);
use Krang::DB qw(dbh);
use Krang::Session qw(%session);
use Krang::User;

# secret salt for creating login cookies
our $SALT = <<END;
   Your heart manholed
   for the installation of feeling.

   Your motherland's parts
   prefabricated.

   Your milk-sister
   a shovel.

   -Paul Celan
END


sub setup {
    my $self = shift;
    $self->start_mode('show_form');
    $self->run_modes(show_form => \&show_form,
                     login     => \&login,
                     logout    => \&logout,
                    );
}

# show the login form
sub show_form {
    my $self     = shift;
    my $query    = $self->query();
    my %arg      = @_;
    my $template = $self->load_tmpl("login_form.tmpl",
                                    associate => $query);
    $template->param(alert => $arg{alert} || $query->param('alert'));
    return $template->output();
}

# handle a login attempt
sub login {
    my $self     = shift;
    my $query    = $self->query();
    my $username = $query->param('username');
    my $password = $query->param('password');
    my $target   = $query->param('target') || './';
    my $dbh      = dbh();

    return $self->show_form(alert =>
                            "Username and password are required fields.")
      unless defined $username and length $username and
             defined $password and length $password;

    # check username and password
    my $user_id = Krang::User->check_auth($username, $password);

    # failure
    return $self->show_form(alert => "Incorrect login, try again.")
      unless $user_id;

    # create a cookie with username, session_id and instance.  Include
    # an MD5 hash with $SALT to allow the PerlAuthenHandler to check
    # for tampering
    my $q = $self->query();
    my $session_id = (defined($ENV{KRANG_SESSION_ID})) ?
      $ENV{KRANG_SESSION_ID} : Krang::Session->create();
    my $instance   = Krang::Conf->instance();
    my %filling    = ( user_id    => $user_id, 
                       session_id => $session_id,
                       instance   => $instance,
                       hash       => md5_hex($user_id . $instance .
                                             $session_id . $SALT) );

    # save user info in new session hash
    $session{user_id}  = $user_id;
    $session{username} = $username;

    # Unload the session if we've created it
    Krang::Session->unload() unless (defined($ENV{KRANG_SESSION_ID}));

    # build the cookie
    my $cookie = $q->cookie(
                            -name   => $instance,
                            -value  => \%filling,
                           );

    # redirect to original destination and set the cookie
    $self->header_props(-uri          => $target,
                        -cookie       => $cookie->as_string);

    $self->header_type('redirect');
    my $output = "Redirect: <a href=\"$target\">$target</a>";
    return $output;
}

1;

