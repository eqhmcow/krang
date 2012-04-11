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
use Krang::ClassLoader DB      => qw(dbh);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'User';
use Krang::ClassLoader 'MyPref';
use Krang::ClassLoader 'PasswordHandler';
use Krang::ClassLoader 'Log'     => qw(debug info);
use Krang::ClassLoader 'Message' => qw(add_message add_alert);
use Krang::ClassLoader Conf      => qw(
  ApachePort
  BadLoginCount
  BadLoginNotify
  BadLoginWait
  Charset
  DefaultLanguage
  FromAddress
  InstanceApachePort
  InstanceDisplayName
  InstanceHostName
  PasswordChangeTime
  PreviewSSL
  Secret
  SMTPServer
);
use CGI::Application::Plugin::RateLimit;
use JSON::Any;

sub setup {
    my $self = shift;
    $self->start_mode('show_form');
    $self->run_modes([qw(show_form login logout login_wait forgot_pw reset_pw new_window)]);
    $self->tmpl_path('Login/');

    # use CAP::RateLimit to limit the number of bad logins
    # per username if we need to
    if (BadLoginCount()) {
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
        my $msg =
            "User '$user' has been locked out of Krang at $url for "
          . BadLoginWait
          . " minutes because of more than "
          . BadLoginCount
          . " failed login attempts.";

        debug(__PACKAGE__ . "->login_wait() - sending email to $email_to : $msg");
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

    add_alert('login_wait', count => BadLoginCount, minutes => BadLoginWait);
    return $self->show_form();
}

# show the login form
sub show_form {
    my $self     = shift;
    my $query    = $self->query();
    my %arg      = @_;
    my $template = $self->load_tmpl("login.tmpl", associate => $query);

    # this can be an arbitrary message coming from some other place
    my $msg = $arg{alert} || $query->param('alert') || $query->param('message');
    add_alert('custom_msg', msg => $msg) if $msg;
    return $template->output();
}

# handle a login attempt
sub login {
    my $self     = shift;
    my $query    = $self->query();
    my $username = $query->param('username');
    my $password = $query->param('password');
    my $dbh      = dbh();

    # if they are already logged in as this user, then don't log them in again
    if( $ENV{REMOTE_USER} ) {
        my ($user) = pkg('User')->find(user_id => $ENV{REMOTE_USER});
        if( $user->login eq $username ) {
            return $self->_redirect_to_root;
        }
    }

    # make sure they don't need to wait
    if (BadLoginCount && length $username) {
        my $rl = $self->rate_limit;
        $rl->identity_callback(sub { $username });
        if ($rl->check_violation(action => 'failed_login')) {
            return $self->login_wait;
        }
    }

    unless (defined $username
        and length $username
        and defined $password
        and length $password)
    {
        add_alert('missing_username_pw');
        return $self->show_form();
    }

    # check username and password
    my $user_id = pkg('User')->check_auth($username, $password);

    # failure
    unless ($user_id) {

        # record the failed login if we are protecting with RateLimit
        if (BadLoginCount) {
            $self->rate_limit->record_hit(action => 'failed_login');
        }
        add_alert('failed_login');
        return $self->show_form();
    }

    return $self->_do_login($user_id);
}

sub _do_login {
    my ($self, $user_id, $mode) = @_;
    my $q = $self->query();

    # if we are enforcing password changes every few days
    if (PasswordChangeTime) {
        my ($user) = pkg('User')->find(user_id => $user_id);
        my $expired = time() - (PasswordChangeTime * 24 * 60 * 60);
        if ($user->password_changed < $expired) {
            $user->force_pw_change(1);
            $user->save();
        }
    }

    # create a cookie with username, session_id and instance.  Include
    # an MD5 hash with Secret to allow the PerlAuthenHandler to check
    # for tampering
    my $session_id = pkg('Session')->create();
    my $instance   = pkg('Conf')->instance();
    my %filling    = (
        user_id    => $user_id,
        session_id => $session_id,
        instance   => $instance,
        next_wid   => 2,
        hash       => md5_hex($user_id . $instance . $session_id . Secret())
    );

    # Propagate user to environment
    $ENV{REMOTE_USER} = $user_id;

    # Put language pref in session
    $session{language} = pkg('MyPref')->get('language') || DefaultLanguage || 'en';

    # Unload the session
    pkg('Session')->unload();

    # build the session cookie (using next available window ID)
    my $authen_cookie = $q->cookie(
        -name  => $instance,
        -value => \%filling,
        -path  => '/'
    );

    # otherwise, store preferences via JSON so the client-side JS can access them
    my %prefs;
    for my $name qw(search_page_size use_autocomplete message_timeout syntax_highlighting language) {
        $prefs{$name} = pkg('MyPref')->get($name);
    }
    my $pref_cookie = $q->cookie(
        -name  => 'KRANG_PREFS',
        -value => JSON::Any->new->encode(\%prefs),
        -path  => '/'
    );

    # and store meta information about this installation/instance of Krang
    my %conf_info = (charset => (Charset() || ''));
    my $conf_cookie = $q->cookie(
        -name  => 'KRANG_CONFIG',
        -value => JSON::Any->new->encode(\%conf_info),
        -path  => '/'
    );

    # instance-specific cookie holding the preview URLs of all sites of this instance
    my $scheme = PreviewSSL ? 'https://' : 'http://';
    my @preview_urls = map {$scheme . $_->preview_url} pkg('Site')->find();
    my $preview_cookie = $q->cookie(
        -name  => 'previewURLs_' . $instance,
        -value => JSON::Any->new->encode(\@preview_urls),
        -path  => '/',
    );

    # and set all four cookies
    $self->header_add(
        -cookie => [$authen_cookie->as_string, $pref_cookie->as_string, $conf_cookie->as_string, $preview_cookie->as_string]);

    # now we're ready to redirect
    return $self->_redirect_to_root();
}

sub _redirect_to_root {
    my ($self) = @_;
    my $target = $self->query->param('target') || './';
    $self->header_add(-uri => $target);
    $self->header_type('redirect');
    return "Redirect: <a href=\"$target\">$target</a>";
}

# handle a logout
sub logout {
    my $self  = shift;
    my $query = $self->query();

    # build a poison cookie
    my $authen_cookie = $query->cookie(
        -name    => pkg('Conf')->instance,
        -value   => "",
        -expires => '-90d',
    );

    # delete the session & window ID
    pkg('Session')->delete($ENV{KRANG_SESSION_ID});

    # redirect to login
    $self->header_props(
        -uri    => 'login.pl',
        -cookie => [$authen_cookie->as_string]
    );
    $self->header_type('redirect');
    return '';
}

sub forgot_pw {
    my $self = shift;
    my $q    = $self->query;
    my $tmpl = $self->load_tmpl('forgot_pw.tmpl', associate => $q);

    if ($q->param('email')) {
        my $email = $q->param('email');
        add_message('forgot_pw');
        $tmpl->param(email_sent => 1);

        # find the user this email address belongs to
        my ($user) = pkg('User')->find(email => $email);
        if ($user) {
            my $port = InstanceApachePort || ApachePort;
            my $site_url = 'http://' . InstanceHostName . ($port == 80 ? '' : ":$port");

            # create the link
            my $instance = pkg('Conf')->instance();
            my $ticket   = md5_hex($user->user_id . $instance . Secret()) . '-' . $user->user_id;

            # send the email
            my $sender = Mail::Sender->new(
                {
                    smtp      => SMTPServer,
                    from      => FromAddress,
                    on_errors => 'die'
                }
            );

            my $msg_tmpl = $self->load_tmpl('forgot_pw_email.tmpl');
            $msg_tmpl->param(
                site_url => $site_url,
                ticket   => $ticket,
                username => $user->login,
            );

            $sender->MailMsg(
                {
                    to      => $email,
                    subject => "[" . InstanceHostName . "] Forgot Password?",
                    msg     => $msg_tmpl->output,
                }
            );
            debug(__PACKAGE__ . "->forgot_pw() - sending forgot_pw email to $email");
        } else {
            debug(__PACKAGE__ . "->forgot_pw() - no user found with email '$email'");
        }
    }

    return $tmpl->output;
}

# intended to only be entered via a link generated by forgot_pw
sub reset_pw {
    my $self = shift;
    my $q    = $self->query;
    my $t    = $q->param('t');

    # decode the ticket
    $t =~ /^(.*)-(\d+)$/;
    my $hash     = $1;
    my $user_id  = $2;
    my $instance = pkg('Conf')->instance();

    debug(__PACKAGE__ . "->reset_pw() - decoding ticket $t: user_id = $user_id'");

    # if it matches what we need it to
    if (md5_hex($user_id . $instance . Secret()) eq $hash) {
        my $new_pw    = $q->param('new_password');
        my $new_pw_re = $q->param('new_password_re');
        my $alert     = '';

        # if we have the necessary info to change it
        if ($new_pw || $new_pw_re) {
            if ($new_pw eq $new_pw_re) {
                my ($user) = pkg('User')->find(user_id => $user_id);
                if ($user) {

                    # check the password constraints
                    my $valid =
                      pkg('PasswordHandler')
                      ->check_pw($new_pw, $user->login, $user->email, $user->first_name,
                        $user->last_name,);

                    if ($valid) {
                        $user->password($new_pw);
                        $user->save;
                        add_message("changed_password");
                        return $self->_do_login($user_id);
                    }
                } else {
                    add_alert('invalid_account');
                }
            } else {
                add_alert('passwords_dont_match');
            }
        }

        my $tmpl = $self->load_tmpl('reset_pw.tmpl', associate => $q);
        return $tmpl->output;
    }
}

1;

