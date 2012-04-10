package Krang::Handler;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::Handler - Krang mod_perl handler

=head1 SYNOPSIS

None.  See F<conf/httpd.conf.tmpl> for usage.

=head1 DESCRIPTION

This module handles Apache requests for Krang.  It contains all the
Apache/mod_perl handlers used by Krang.

The basic order of events is:

=over 4

=cut

use Apache::Constants qw(:response :common M_GET);
use Apache::Cookie;
use Apache::SizeLimit;
use Apache::URI;
use Apache;
use CGI ();
use Carp qw(croak);
use Digest::MD5 qw(md5_hex md5);
use File::Spec::Functions qw(splitdir rel2abs catdir catfile);
use HTTP::BrowserDetect;
use Krang::ClassLoader 'CGI::Login';
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'File';
use Krang::ClassLoader 'Cache';
use Krang::ClassLoader 'HTMLTemplate';
use Krang::ClassLoader Conf => qw(
  KrangRoot
  PasswordChangeTime
  ApacheMaxSize
  Secret
  ApacheMaxUnsharedSize
  BrowserSpeedBoost
  DefaultLanguage
  ErrorNotificationEmail
  SMTPServer
  FromAddress
);
use Krang::ClassLoader Log => qw(critical info debug);
use Krang::ClassLoader 'AddOn';
use Krang;
use Krang::ClassLoader Session => qw(%session);
use CSS::Minifier::XS;
use JavaScript::Minifier::XS;
use Mail::Sender;
use Data::Dumper;
use URI::Escape qw(uri_escape);

BEGIN { pkg('AddOn')->call_handler('InitHandler') }

if (ApacheMaxSize) {
    Apache::SizeLimit->set_max_process_size(ApacheMaxSize);
} elsif (!defined ApacheMaxSize) {
    Apache::SizeLimit->set_max_process_size(64000);    # 64MB by default
}
Apache::SizeLimit->set_max_unshared_size(ApacheMaxUnsharedSize) if ApacheMaxUnsharedSize;

=item Krang::Handler->trans_handler

Responsible for setting Krang instance name and propagating it
to the environment (KRANG_INSTANCE).  Responsible for re-writing
requests internally to properly locate files in the case of
"root"-flavor requests.  E.g.:

Both requests:

  http://my-krang/instance1/someasset.gif
  http://my-krang/someasset.gif

 ...translate to...

  /path/to/document/root/someasset.gif

=cut

# Re-write the incoming request, based on Krang Instance rules:
#
# flavor == "instance" :  Instance name should be set, or die()
# flavor == "root"     :  If no instance name, must be in root directory.  Show list of instances.
#                      :  If we have an instance name, it should match first directory in path
#                      :  If in instance path, rewrite uri to point to real assets in htdocs root.

sub trans_handler ($$) {
    my ($self, $r) = @_;
    my $uri  = $r->uri;

    debug("Krang::Handler:  REQUEST: $uri");

    # if it's a request for a /static file then strip off the static
    # prefix that looks like "/static/XXXX" where "XXXX" is the install_id
    if ($uri =~ /^\/static\//) {
        debug("Krang::Handler:  URI is for static resource");

        # find the appropriate krang file
        my $file = $uri;
        $file =~ s{^/static/[^/]+/}{};
        $file = pkg('File')->find(catfile('htdocs', $file));
        if( $file ) {
            debug("Krang::Handler:  Rewriting to $file");
        } else {
            debug("Krang::Handler:  Could not find file");
            return NOT_FOUND unless $file;
        }

        if (BrowserSpeedBoost) {
            debug("Krang::Handler:  Setting far future expiration date: Mon, 28 Jul 2014 23:30:00 GMT");
            # make it expire waaaaay in the future since we know the resource won't change
            $r->err_header_out('Expires'       => 'Mon, 28 Jul 2014 23:30:00 GMT');
            $r->err_header_out('Cache-Control' => 'max-age=315360000');

            if ($uri =~ /combined.\w\w\.js$/ && $self->_can_handle_gzip($r)) {
                # the prebuilt combined JS file needs to be redirected to the gzip one if we can
                $file = "$file.gz";
                $r->err_header_out('Content-Encoding' => 'gzip');
                debug("Krang::Handler:  Rewriting to use pre-compressed file $file");
            } elsif ($uri =~ /\.(css|js|html)$/) {
                # if it's a CSS/JS/HTML file then let's minify it and optionally compress it
                my $type = $1;
                my $new_file = $self->_minify_and_gzip($r, $file, $type);
                $file = $new_file if $new_file;
                debug("Krang::Handler:  Minifying and compressing on the fly to $file");
            }
        }

        $r->filename($file);
        return OK;
    }

    return OK if $r->prev && $r->prev->uri =~ /^\/static\//;

    # Only handle main requests, unless this is a request for bug.pl
    # which happens on redirects from ISEs
    unless ($r->is_initial_req() or $uri =~ /\/bug\.pl/) {
        debug("Krang::Handler:  Don't rewrite internal redirects");
        return DECLINED;
    }

    # Read directory configuration for this request
    my $instance_name = $r->dir_config('instance');
    $instance_name = '' unless (defined($instance_name));
    my $flavor = $r->dir_config('flavor');

    # Are we in the context of an Instance server?
    if ($flavor eq 'instance') {
        unless (length($instance_name)) {
            my $error = "No instance name set for this Krang instance";
            critical($error);
            die($error);
        }

        # Set current instance, or die trying
        debug("Krang::Handler:  Setting instance to '$instance_name'");
        pkg('Conf')->instance($instance_name);

        # Propagate the instance name to the CGI-land
        $r->cgi_env('KRANG_INSTANCE' => $instance_name);

        # Handle DirectoryIndex case...
        $uri .= 'workspace.pl' if ($uri =~ /\/$/);

        # now map to a file on disk with Krang::File
        my $file = pkg('File')->find("htdocs/$uri");
        $r->filename($file);
        return OK;
    }

    ## We're now in the context of a "root"-flavored instance... directory city, baby.
    if (length($instance_name)) {

        # We have an instance name.  We should be in a matching path
        unless ($uri =~ /^\/$instance_name/) {
            my $error = "Expected uri like '/$instance_name\*', got '$uri' instead";
            critical($error);
            die($error);
        }

        # Set current instance, or die trying
        debug("Krang::Handler:  Setting instance to '$instance_name'");
        pkg('Conf')->instance($instance_name);

        # Propagate the instance name to the CGI-land
        $r->cgi_env('KRANG_INSTANCE' => $instance_name);

        # Rewrite the current uri to send request back to the real assets in the root
        my $new_uri = $uri;
        $new_uri =~ s/^\/$instance_name//;

        # Handle root case: workspace.pl
        $new_uri = "/workspace.pl" if (($new_uri eq '/') || $new_uri eq '');

        # map to filename on disk
        my $fq_filename = pkg('File')->find("htdocs/$new_uri");
        $r->filename($fq_filename);

        return OK;

    } else {

        # allow requests for static files through if they're present
        # including things in wysiwyg editors
        if ($uri =~ /\.(ico|css|js|jpg|gif|png|js|html?)$/i || $uri =~ /xinha/) {
            my $filename = pkg('File')->find("htdocs/$uri");
            if ($filename) {
                $r->filename($filename);
                return OK;
            }
        }

        # stop other requests unless they're for the root
        unless( $uri eq '/' ) {
            debug("Can't access anything but root or static files if no instance is set");
            return FORBIDDEN;
        }

        # We're looking at the root.  Set handler to show list of instances
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&instance_menu);

        return DECLINED;

    }
}

=item Krang::Handler->access_handler

Access Control.  Checks to make sure the user has a browser that will
work with Krang.

=cut

# Check the browser using HTTP::BrowserDetect and bounce old browsers
# before they can get into trouble.
sub access_handler ($$) {
    my ($self, $r) = @_;

    my %allow_browsers = $self->supported_browsers;

    my %engine_of = (
        netscape  => 'Gecko',
        mozilla   => 'Gecko',
        firefox   => 'Gecko',
        ie        => 'IE',
        safari    => 'WebKit',
        konqueror => 'WebKit',
        chrome    => 'WebKit',
    );

    my $bd = $r->pnotes('browser_detector')
      || HTTP::BrowserDetect->new($r->header_in('User-Agent'));
    foreach my $browser (keys %allow_browsers) {
        if ($bd->$browser) {
            $allow_browsers{$browser} =~ /(\d)+(\.\d+)?/;
            my ($major, $minor) = ($1, $2);
            $minor ||= ".0";
            if ($bd->major > $major
                or ($bd->major == $major && $bd->minor >= $minor))
            {
                if ($engine_of{$browser} eq 'Gecko') {
                    my $gecko_version = $bd->gecko_version();
                    debug("Krang::Handler:  Gecko Version: ".$gecko_version);
                    $r->subprocess_env("KRANG_GECKO_VERSION" => $gecko_version);
                }

                $r->subprocess_env("KRANG_BROWSER_ENGINE"         => $engine_of{$browser});
                $r->subprocess_env("KRANG_BROWSER_MAJOR_VERSION"  => $bd->major);
                return OK;
            }
        }
    }

    # failure
    debug("Krang::Handler:  Unsupported browser detected: " . ($r->header_in('User-Agent') || ''));
    $r->custom_response(FORBIDDEN, $self->forbidden_browser_message);
    return FORBIDDEN;
}

=item supported_browsers()

The list of browsers and versions to allow as supported browsers.

=cut

sub supported_browsers {
    my $self = shift;

    return (
        netscape  => 7.1,
        ie        => 6,
        mozilla   => 5,
        firefox   => 1.5,
        safari    => 1.3,
        konqueror => 1,
        chrome    => 10,
    );
}

=item forbidden_browser_message()

The text of the error message returned to unsupported browsers.

=cut

sub forbidden_browser_message {
    my $self = shift;

    return
      "<h1>Unsupported browser detected.</h1><p>This application requires Firefox 1.5+, Safari 1.3+, Internet Explorer 6+, Mozilla 1.7+, Netscape 7+ or Konqueror 1+.</p>";
}

=item Krang::Handler->authen_handler

Authentication.  Checks for an auth cookie.  If found and valid, the request is 
associated with the user_id via the $request->connection->user() 
method.  The effect of this is that $query->remote_user() and 
C<$ENV{REMOTE_USER}> will properly report the user who is logged in.

=cut

# Attempt to retrieve user identity from session cookie.
# Set REMOTE_USER and KRANG_SESSION_ID if successful.
sub authen_handler ($$) {
    my ($self, $r) = @_;
    my $uri = $r->uri;

    # If the request (or redirected request) was for a static item, let it through
    return OK if $uri =~ /^\/static\// or ($r->prev && $r->prev->uri =~ /^\/static\//);

    # Only handle main requests, unless request is for bug.pl (which happens on ISE redirects)
    return DECLINED unless $r->is_initial_req() or $uri =~ /\/bug\.pl/;

    # Get Krang instance name
    my $instance = pkg('Conf')->instance();

    # Get cookies
    my %cookies = Apache::Cookie->new($r)->parse;

    # If there's no ID or no session cookie, redirect to Login
    unless ($cookies{$instance}) {
        # no cookie, redirect to login
        debug("Krang::Handler:  No cookie found, passing Authen without user login");
        return OK;
    }

    # Validate authen cookie
    my %cookie     = $cookies{$instance}->value;
    my $session_id = $cookie{session_id};
    my $hash       = md5_hex($cookie{user_id} . $cookie{instance} . $session_id . Secret());
    if ($cookie{hash} ne $hash or $cookie{instance} ne pkg('Conf')->instance()) {
        # invalid cookie, send to login
        critical("Invalid cookie found, possible breakin attempt from IP "
              . $r->connection->remote_ip
              . ".  Passing Authen without user login.");
        return OK;
    }

    # A non-PERL request (e.g. image), bug, or help file: let it through
    # (we are already authenticated)
    if ($uri !~ /(\.pl|\/|$instance)$/ || $uri =~ /\/bug\.pl$/ || $uri =~ /\/help\.pl$/) {
        # We are authenticated:  Setup REMOTE_USER
        $r->connection->user($cookie{user_id});
        return OK;
    }

    # Get query
    my %args = $r->args();

    # Check for invalid session
    unless (pkg('Session')->validate($session_id)) {
        debug("Krang::Handler:  Invalid session '$session_id'. Wiping its cookie.");
        return OK;
    }

    # We have a valid session/user!  Setup REMOTE_USER
    $r->connection->user($cookie{user_id});

    # Propagate user & window to CGI-land via the environment
    $r->subprocess_env('KRANG_SESSION_ID' => $session_id);

    # We are authenticated, we've got a valid session:
    # Redirect to workspace if user typed a login URI in a new window
    my $login_uri = $self->login_uri;
    if ($uri =~ /\Q$login_uri\E/) {
        if (!$args{rm} || ($args{rm} && $args{rm} ne 'logout')) {
            debug("Krang::Handler: Already logged in, redirecting to workspace");
            return $self->_redirect_to_workspace($r, $instance);
        }
    }
    pkg('Session')->unload();

    return OK;
}

=item Krang::Handler->authz_handler

Authorization. Enforces "require valid-user" only.  IOW, 
if a user is specified, they are authorized.  If no user
has been specified (via the authen_handler), the request is
redirected to the login application.

Also, if C<PasswordChangeTime> is set to a non-zero value,
we check to see if the user's C<force_pw_change> has been
set. If it has, the user is redirected to C<force_pw_change>
runmode of the C<CGI::MyPref> class.

=cut

# Authorization
sub authz_handler ($$) {
    my ($self, $r) = @_;
    my $uri = $r->uri;

    # If the request (or redirected request) was for a static item, let it through
    return OK if $uri =~ /^\/static\// or ($r->prev && $r->prev->uri =~ /^\/static\//);

    # Only handle main requests, unless this is a request for bug.pl
    # which happens on redirects from ISEs
    return DECLINED unless $r->is_initial_req() or $uri =~ /\/bug\.pl/;

    my $path     = $uri;
    my $instance = pkg('Conf')->instance();
    my $flavor   = $r->dir_config('flavor');

    # always allow access to the specified apps
    my @unprotected_uri = $self->unprotected_uri();
    foreach my $uu (@unprotected_uri) {
        if (   ($flavor eq 'root' and $path =~ m!^/$instance/$uu!)
            or ($flavor eq 'instance' and $path =~ m!^/$uu!))
        {
            return OK;
        }
    }

    # always allow access to the CSS file and images - needed before
    # login to display the login screen
    return OK
      if $path =~ m!krang_login$!
          or $path =~ m!\.(gif|jpg|jpeg|png|css|js|ico)$!;

    # If user is logged in
    if (my $user_id = $r->connection->user) {

        # if we are enforcing changes in pw and the user's not
        # already trying to change their pw
        if (PasswordChangeTime && $path !~ /my_pref\.pl/) {

            # check the last time the user changed their pw
            eval "require pkg('User')";
            my ($user) = pkg('User')->find(user_id => $user_id);
            if ($user->force_pw_change) {
                return $self->_redirect_to_change_pw($r, $flavor, $instance);
            } else {
                return OK;
            }
        } else {

            # if we're logged in, we're good
            return OK;
        }
    }

    # No user?  Not a request to login?  Redirect the user to login!
    return $self->_redirect_to_login($r, $flavor, $instance);
}

=item Krang::Handler->log_handler

Logging.  When the application is running under Apache::Registry (not
in CGI_MODE) this handler gets error messages out of
C<< $r->notes() >> and logs them with Krang::Log.

=cut

sub log_handler ($$) {
    my ($pkg, $r) = @_;

    # in Apache::Registry mode this is where we collect die() and
    # warn()s since they don't get caught by Krang::ErrorHandler
    if ($ENV{GATEWAY_INTERFACE} =~ /Perl/) {
        if (my $err = $r->notes('error-notes')) {
            critical($err);
        }
    }

    # must make sure the cache is off at the end of the request
    if (pkg('Cache')->active()) {
        critical("Cache still on in log handler!  This cache was started at "
              . join(', ', @{pkg('Cache')->stack(-1)})
              . ".");
        pkg('Cache')->stop() while (pkg('Cache')->active());
    }

    return OK;
}

=item Krang::Handler->cleanup_handler

Cleanup. We use L<Apache::SizeLimit> to limit the size of the individual
Apache processes. Also, if an ISE occurred during the handling of this request
we send an optional email to any addresses configured by the C<ErrorNotificationEmail>
directive.

=back

=cut

sub cleanup_handler ($$) {
    my ($pkg, $r) = @_;
    return DECLINED unless $r->is_main;
    my $status = $r->last->status;

    if ($status == SERVER_ERROR && ErrorNotificationEmail) {
        my $error = $r->notes('error-notes') || $ENV{ERROR_NOTES};
        
        # dont worry about clients hitting the "Stop" button
        return DECLINED if $error =~ /client aborted\?/;

        # format an email message with all of the information that we want
        my $line = ('=' x 40);
        my $msg =
            "INSTANCE\n$line\n%s (%s)\n\nUSER\n$line\n%s (#%s)\n\nTIMESTAMP\n$line\n%s\n\n"
          . "SERVER\n$line\n%s\nURL\n$line\n%s\n\nPERL ERROR\n$line\n%s\n"
          . "REQUEST\n$line\n%s\nENV\n$line\n%s\nHTTP STATUS\n$line\n%s";
        my $instance     = Arcos::Conf->instance();
        my $instance_url = $r->hostname;
        my $user_id      = $r->user;
        my $timestamp    = scalar localtime;
        my $login        = '';
        if ($user_id) {
            eval "require pkg('User')";
            my ($user) = pkg('User')->find(user_id => $user_id);
            $login = $user->login if $user;
        }
        my $server  = `hostname`;
        my $url     = $r->uri;
        my $request = $r->as_string();
        my $dumper  = Data::Dumper->new([\%ENV]);
        $dumper->Terse(0);
        $dumper->Indent(1);
        $dumper->Sortkeys(1);
        $dumper->Maxdepth(0);
        $msg = sprintf($msg,
            $instance, $instance_url, $login,   $user_id,      $timestamp, $server,
            $url,      $error,        $request, $dumper->Dump, $r->status);

        # now send the email to all configured recipients
        my @email = split(/\s*,\s*/, ErrorNotificationEmail);
        my $sender =
          Mail::Sender->new({smtp => SMTPServer, from => FromAddress, on_errors => 'die'});
        $sender->MailMsg(
            {
                to      => \@email,
                subject => "[Krang] Internal Server Error - $instance",
                msg     => $msg,
            }
        );
    }
    pkg('Session')->clear_last_session_id();
    $r->subprocess_env('KRANG_SESSION_ID' => undef);
    Apache::SizeLimit->handler($r);
}

=head1 INTERFACE

Following are methods which can be overridden in sub-classes.

=over 4

=item unprotected_uri()

Return a list of URIs which should never be restricted by login.

=cut

sub unprotected_uri {
    my $self = shift;

    # Just the login.pl, by default
    my @uris = ($self->login_uri);

    return @uris;
}

=item login_uri()

The URI to which users should be redirected if they fail authorization.

=cut

sub login_uri {
    my $self = shift;

    return qw(login.pl);
}

#############################
####  INTERNAL HANDLERS  ####
#############################

# display a menu of available instances
sub instance_menu {
    my $r = shift;

    # setup the instance loop
    my (@loop, @instances);
    @instances = pkg('Conf')->instances();

    # if there's only one instance, just go there
    if (scalar @instances == 1) {
        $r->headers_out->{Location} = '/' . $instances[0] . '/';
        return REDIRECT;

        # else, show the menu
    } else {
        my $template = pkg('HTMLTemplate')->new(
            filename => 'instance_menu.tmpl',
            cache    => 1
        );

        foreach my $instance (@instances) {
            pkg('Conf')->instance($instance);
            push(
                @loop,
                {
                    InstanceName        => $instance,
                    InstanceDisplayName => (pkg('Conf')->InstanceDisplayName || $instance),
                }
            );
        }
        $template->param(instance_loop => \@loop);

        # output HTML
        $r->send_http_header('text/html');
        print $template->output();
        return OK;
    }

}

# the site-server transhandler maps requests to a site's preview or
# publish path
sub siteserver_trans_handler ($$) {
    my ($self, $r) = @_;
    my $host = $r->hostname;
    my $port = $r->get_server_port;

    # add in port number if necessary
    $host .= ":$port" unless $port == 80;

    # find a site for this hostname, looking in all instances
    eval "require " . pkg('Site') or die $@;
    my $path;
  INSTANCE: foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        my @sites = pkg('Site')->find();
        foreach my $site (@sites) {
            my $url         = $site->url;
            my $preview_url = $site->preview_url;

            # is it a match?
            if ($url eq $host) {
                $path = $site->publish_path;
                last INSTANCE;
            } elsif ($preview_url eq $host) {
                $path = $site->preview_path;
                last INSTANCE;
            }
        }
    }

    # Didn't find a site?  Null out doc root and forbid request
    unless ($path) {
        $r->document_root(catdir(KrangRoot, "tmp"));
        debug("Not site found for $host");
        return FORBIDDEN;
    }

    # Set up DOCUMENT_ROOT
    $r->document_root($path);

    # map the URI to a filename
    my $filename = catfile($path, $r->uri);
    $r->filename($filename);
    return OK;
}

sub _redirect_to_login {
    my ($self, $r, $flavor, $instance) = @_;
    my $login_app = $self->login_uri();

    # preserve the target URL we were trying to get
    my $uri = $r->uri;
    $uri =~ s/\?.*//;
    if( $uri ne '/' ) {
        $login_app .= '?target=' . uri_escape($uri);
    }

    # for ajaxy redirect
    my %content = $r->content;
    if ($content{ajax}) {
        $login_app .= '&rm=redirect_to_login&ajax=1';
    }

    my $new_uri = ($flavor eq 'instance' ? "/$login_app" : "/$instance/$login_app");

    return $self->_do_redirect($r, $new_uri);
}

sub _redirect_to_workspace {
    my ($self, $r, $instance) = @_;

    my $app = "workspace.pl";
    my $new_uri = $r->dir_config('flavor') eq 'instance' ? "/$app" : "/$instance/$app";

    return $self->_do_redirect($r, $new_uri);
}

sub _redirect_to_change_pw {
    my ($self, $r, $flavor, $instance) = @_;

    my $app = 'my_pref.pl?rm=force_pw_change';
    my $new_uri = ($flavor eq 'instance' ? "/$app" : "/$instance/$app");

    return $self->_do_redirect($r, $new_uri);
}

sub _do_redirect {
    my ($self, $r, $new_uri) = @_;

    $r->err_header_out(Location => $new_uri);
    my $output = "Redirect: <a href=\"$new_uri\">$new_uri</a>";

    return REDIRECT;
}

sub _can_handle_gzip {
    my ($self, $r) = @_;
    if ($r->header_in('Accept-Encoding') && $r->header_in('Accept-Encoding') =~ /gzip/i) {
        my $bd = $r->pnotes('browser_detector');
        if (!$bd) {
            $bd = HTTP::BrowserDetect->new($r->header_in('User-Agent'));
            $r->pnotes(browser_detecor => $bd);
        }
        if ($bd->ie && $bd->version <= 6) {
            return 0;
        } else {
            return 1;
        }
    } else {
        return 1;
    }
}

sub _minify_and_gzip {
    my ($self, $r, $file, $type) = @_;
    my $new_file = $file;

    # can we minify it?
    if ($type eq 'css' || $type eq 'js') {
        $new_file =~ s/\.$type$/.minified.$type/;

        # create the new file only if it doesn't exist and is newer than the original
        unless (-e $new_file && (stat $new_file)[9] > (stat $file)[9]) {

            # minify the file and save it
            local $/;
            open(my $ASSET, '<', $file) or die "Could not open $file for reading: $!";
            my $content = <$ASSET>;
            close($ASSET);

            if ($type eq 'css') {
                eval { $content = CSS::Minifier::XS::minify($content) };
            } elsif ($type eq 'js') {
                eval { $content = JavaScript::Minifier::XS::minify($content) };
            }

            if ($@) {
                warn "Could not minify file $file: $@\n";
                return;
            } else {
                open($ASSET, '>', $new_file) or die "Could not open $new_file for writing: $!";
                print $ASSET $content;
                close($ASSET);
            }
        }
    }

    # can we compress it?
    if ($self->_can_handle_gzip($r)) {
        my $compressed_file = $new_file . '.gz';
        unless (-e $compressed_file && (stat $compressed_file)[9] > (stat $new_file)[9]) {

            # we could replace this with some Perl module to do the gzip compression
            # to avoid the overhead of a system call, but it's just a 1 time hit for
            # the file the first time and is really negligible
            system("gzip -c $new_file > $compressed_file") == 0
              or die "Could not compress file $new_file!";
        }
        $r->err_header_out('Content-Encoding' => 'gzip');
        $new_file = $compressed_file;
    }
    return $new_file;
}

1;
