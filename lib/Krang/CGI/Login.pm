package Krang::CGI::Login;
use Krang::ClassFactory qw(pkg);
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


use Krang::ClassLoader base => 'CGI';
use Digest::MD5 qw(md5_hex md5);
use Krang::ClassLoader DB => qw(dbh);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'User';
use Krang::ClassLoader Conf => qw(InstanceDisplayName BadLoginCount BadLoginWait PasswordChangeTime);
use CGI::Application::Plugin::RateLimit;

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
    $self->run_modes(show_form  => 'show_form',
                     login      => 'login',
                     logout     => 'logout',
                     login_wait => 'login_wait',
                    );
    $self->tmpl_path('Login/');

    # use CAP::RateLimit to limit the number of bad logins
    # per username if we need to
    if( BadLoginCount() ) {
        my $rl = $self->rate_limit();
        $rl->protected_actions(
            failed_login => {
                timeframe => BadLoginWait() . 'm',
                max_hits  => BadLoginCount(),
            },
        );
        $rl->violation_mode('login_wait');
    }
}

# show the user a message that informs them they have failed
# login too many times and need to wait
sub login_wait {
    my $self = shift;
    return $self->show_form(
        alert => "Invalid login. You have failed " 
            . BadLoginCount . " and must wait " 
            . BadLoginWait . " minutes before logging in again."
    );
}

# show the login form
sub show_form {
    my $self     = shift;
    my $query    = $self->query();
    my %arg      = @_;
    my $template = $self->load_tmpl("login.tmpl",
                                    associate => $query);
    $template->param(alert => $arg{alert} || $query->param('alert'));
    $template->param(instance_name => InstanceDisplayName);
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

    # if we're protecting with RateLimit
    if( BadLoginCount ) {
        my $rl = $self->rate_limit;
        $rl->identity_callback(sub { $username });
        $rl->dbh($dbh);
        # if they've exceeded their limit, stop 'em
        if( BadLoginCount && $rl->check_violation(action => 'failed_login') ) {
            return $self->login_wait 
        }
    }

    return $self->show_form(alert =>
                            "User name and password are required fields.")
      unless defined $username and length $username and
             defined $password and length $password;

    # check username and password
    my $user_id = pkg('User')->check_auth($username, $password);

    # failure
    unless( $user_id ) {
        # record the failed login if we are protecting with RateLimit
        if( BadLoginCount ) {
            $self->rate_limit->record_hit(action => 'failed_login');
        }
        return $self->show_form(
            alert => "Invalid login.  Please check your user name and password and try again."
        );
    }

    # if we are enforcing password changes every few days
    if( PasswordChangeTime ) {
        my ($user) = pkg('User')->find(user_id => $user_id);
        my $expired = time() - (PasswordChangeTime * 24 * 60 * 60); 
        if( $user->password_changed < $expired ) {
            $user->force_pw_change(1);
            $user->save();
        }
    }

    # create a cookie with username, session_id and instance.  Include
    # an MD5 hash with $SALT to allow the PerlAuthenHandler to check
    # for tampering
    my $q = $self->query();
    my $session_id = (defined($ENV{KRANG_SESSION_ID})) ?
      $ENV{KRANG_SESSION_ID} : pkg('Session')->create();
    my $instance   = pkg('Conf')->instance();
    my %filling    = ( user_id    => $user_id, 
                       session_id => $session_id,
                       instance   => $instance,
                       hash       => md5_hex($user_id . $instance .
                                             $session_id . $SALT) );

    # Propagate user ID to environment
    $ENV{REMOTE_USER}  = $user_id;

    # Unload the session if we've created it
    pkg('Session')->unload() unless (defined($ENV{KRANG_SESSION_ID}));

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

# handle a logout
sub logout {
    my $self     = shift;
    my $query    = $self->query();

    # delete the session
    pkg('Session')->delete($ENV{KRANG_SESSION_ID});

    # build a poison cookie
    my $cookie = $query->cookie(
                            -name   => pkg('Conf')->instance,
                            -value  => "",
                            -expires=>'-90d',
                           );
    
    # redirect to login
    $self->header_props(-uri    => 'login.pl',
                        -cookie => $cookie->as_string);
    $self->header_type('redirect');
    return "";
}

1;

