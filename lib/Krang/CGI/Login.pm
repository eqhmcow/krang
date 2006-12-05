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
use Krang::ClassLoader 'Log' => qw(debug);
use Krang::ClassLoader Conf => qw(
    BadLoginCount
    BadLoginWait
    BadLoginNotify
    PasswordChangeTime
    SMTPServer
    FromAddress
    InstanceHostName
    InstanceDisplayName
    InstanceApachePort
    ApachePort
);
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
        my $rl = $self->rate_limit;
        $rl->protected_actions(
            failed_login => {
                timeframe => BadLoginWait() . 'm',
                max_hits  => BadLoginCount(),
            },
        );
        $rl->violation_mode('login_wait');
        $rl->dbh(dbh);
    }
}

# show the user a message that informs them they have failed
# login too many times and need to wait
sub login_wait {
    my $self = shift;

    # send an email to the BadLoginNotify email address if it
    # exists
    if (BadLoginNotify) {
        my $email_to = $ENV{KRANG_TEST_EMAIL} || BadLoginNotify;
        my $user     = $self->query->param('username');
        my $url      = 'http://' . InstanceHostName . ':' . (InstanceApachePort || ApachePort);
        my $msg      =
            "User '$user' has been locked out of Krang at $url for "
          . BadLoginWait
          . " minutes because of more than "
          . BadLoginCount
          . " failed login attempts.";

        debug( __PACKAGE__ . "->send() - sending email to $email_to : $msg" );
        my $sender = Mail::Sender->new(
            {
                smtp      => SMTPServer,
                from      => FromAddress,
                on_errors => 'die'
            }
        );

        $sender->MailMsg(
            {
                to      => $email_to,
                subject => "[Krang] Repeated failed login attempts",
                msg     => $msg,
            }
        );
    }

    return $self->show_form(
        alert => "Invalid login. You have failed more than " 
            . BadLoginCount . " login attempts and must wait " 
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
            my $rl = $self->rate_limit;
            $rl->identity_callback(sub { $username });
            $rl->record_hit(action => 'failed_login');
            if( $rl->check_violation(action => 'failed_login') ) {
                return $self->login_wait;
            }
        }
        return $self->show_form(
            alert => "Invalid login. Please check your user name and password and try again."
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

