package Krang::Handler;
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


=item Krang::Handler->authen_handler

Authentication.  Checks for an auth cookie.  If found and valid, the request is 
associated with the user_id via the $request->connection->user() 
method.  The effect of this is that $query->remote_user() and 
$ENV{REMOTE_USER} will properly report the user who is logged in.


=item Krang::Handler->authz_handler

Authorization.  Currently enforced "require valid-user" only.  IOW, 
if a user is specified, they are authorized.  If no user
has been specified (via the authen_handler), the request is
redirected to the login application.


=back

=head1 INTERFACE

None.

=cut

use Krang;
use Krang::CGI::Login;
use Apache::URI;
use Apache::Constants qw(:response);
use Apache::Cookie;
use File::Spec::Functions qw(splitdir rel2abs catdir);
use Carp qw(croak);
use Krang::Conf qw(KrangRoot);
use HTML::Template;
use Digest::MD5 qw(md5_hex md5);
use Krang::Log qw(critical info debug);


# Login app name
use constant LOGIN_APP => 'login.pl';



##########################
####  PUBLIC METHODS  ####
##########################


# Re-write the incoming request, based on Krang Instance rules:
#
# flavor == "instance" :  Instance name should be set, or die()
# flavor == "root"     :  If no instance name, must be in root directory.  Show list of instances.
#                      :  If we have an instance name, it should match first directory in path
#                      :  If in instance path, rewrite uri to point to real assets in htdocs root.
#
sub trans_handler ($$) {
    my $self = shift;
    my ($r) = @_;

    # Only handle main requests
    unless ( $r->is_initial_req() ) {
        return DECLINED;
    }

    # Read directory configuration for this request
    my $instance_name = $r->dir_config('instance');
    $instance_name = '' unless (defined($instance_name));
    my $flavor = $r->dir_config('flavor');
    my $uri = $r->uri();

    # Are we in the context of an Instance server?
    if ($flavor eq 'instance') {
        die ("No instance name set for this Krang instance") unless (length($instance_name));

        # Set current instance, or die trying
        debug("Krang::Handler:  Setting instance to '$instance_name'");
        Krang::Conf->instance($instance_name);

        # Propagate the instance name to the CGI-land
        $r->cgi_env('KRANG_INSTANCE' => $instance_name);

        # Handle DirectoryIndex case...
        $uri .= 'index.html' if ($uri =~ /\/$/);
        $r->uri($uri);

        # Our work is done -- we outta 'ere
        return DECLINED;
    }


    ## We're now in the context of a "root"-flavored instance... directory city, baby.
    if (length($instance_name)) {

        # We have an instance name.  We should be in a matching path
        die ("Expected uri like '/$instance_name\*', got '$uri' instead") 
          unless ($uri =~ /^\/$instance_name/);

        # Set current instance, or die trying
        debug("Krang::Handler:  Setting instance to '$instance_name'");
        Krang::Conf->instance($instance_name);

        # Propagate the instance name to the CGI-land
        $r->cgi_env('KRANG_INSTANCE' => $instance_name);

        # Rewrite the current uri to send request back to the real assets in the root
        my $new_uri = $uri;
        $new_uri =~ s/^\/$instance_name//;

        # Handle root case: index.html
        $new_uri = "/index.html" if (($new_uri eq '/') || $new_uri eq '');

        my $fq_filename = $r->document_root() . $new_uri;
        $r->filename($fq_filename);

        return OK;

    } else {

        # Allow requests for other assets to pass through normally
        return DECLINED unless ($uri eq '/');

        # We're looking at the root.  Set handler to show list of instances
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&instance_menu); 

        return DECLINED;

    }
}


# Attempt to retrieve user adentity from session cookie.
# Set REMOTE_USER and KRANG_SESSION_ID if successful
sub authen_handler ($$) {
    my $self = shift;
    my ($r) = @_;

    # Only handle main requests
    unless ( $r->is_initial_req() ) {
        return DECLINED;
    }

    # Get Krang instance name
    my $instance  = Krang::Conf->instance();

    my %cookies = Apache::Cookie->new($r)->parse();
    unless ($cookies{$instance}) {
        # no cookie, redirect to login
        debug("No cookie found, passing Authen without user login");
        return OK;
    }

    # validate cookie
    my %cookie = $cookies{$instance}->value;
    my $session_id = $cookie{session_id};
    my $hash = md5_hex($cookie{user_id} . $cookie{instance} . 
                       $session_id . $Krang::CGI::Login::SALT);
    if ($cookie{hash} ne $hash or $cookie{instance} ne $instance) {
        # invalid cookie, send to login
        critical("Invalid cookie found, possible breakin attempt from IP " . 
                 $r->connection->remote_ip . ".  Passing Authen without user login.");
        return OK;
    }

    # Validate session by trying to load session
    debug("Krang::Handler:  Loading session '$session_id'");
    eval { Krang::Session->load($session_id); };

    # Check for invalid session
    if ($@) {
        debug("Error loading session: $@");
        return OK;
    }

    # Unload the session so that we don't block later
    debug("Krang::Handler:  UN-Loading session");
    Krang::Session->unload();

    # We have a valid cookie/user!  Setup REMOTE_USER
    $r->connection->user($cookie{user_id});

    # Propagate it to CGI-land via the environment
    $r->cgi_env('KRANG_SESSION_ID' => $cookie{session_id});

    return OK;
}


# Authorization
sub authz_handler ($$) {
    my $self = shift;
    my ($r) = @_;

    # Only handle main requests
    unless ( $r->is_initial_req() ) {
        return DECLINED;
    }

    my $path      = $r->parsed_uri()->path();
    my $instance  = Krang::Conf->instance();
    my $flavor    = $r->dir_config('flavor');

    # always allow access to the login app
    my $login_app = LOGIN_APP;
    if (($flavor eq 'root'     and $path =~ m!^/$instance/$login_app!) or 
        ($flavor eq 'instance' and $path =~ m!^/$login_app!) or
        ($path =~ m!^/$instance/env\.!) or
        ($path =~ m!^/env\.!)
       ) {
        return OK;
    }

    # If user is logged in, we're done
    return OK if (defined($r->connection->user()));

    # No user?  Not a request to login?  Redirect the user to login!
    return $self->_redirect_to_login($r, $flavor, $instance);
}




#############################
####  INTERNAL HANDLERS  ####
#############################

# display a menu of available instances
sub instance_menu {
    my ($r) = @_;

    my $template = HTML::Template->new(filename => 'instance_menu.tmpl',
                                       cache    => 1,
                                       path     => 
                                       rel2abs(catdir(KrangRoot,"templates")));

    # setup the instance loop
    my @loop;
    foreach my $instance (Krang::Conf->instances()) {
        push(@loop, { InstanceName => $instance });
    }
    $template->param(instance_loop => \@loop);

    # output HTML
    print $template->output();

    return OK;
}




###########################
####  PRIVATE METHODS  ####
###########################

sub _redirect_to_login {
    my $self = shift;
    my ($r, $flavor, $instance) = @_;

    my $login_app = LOGIN_APP;
    my $new_uri = ($flavor eq 'instance' ? "/$login_app" : "/$instance/$login_app");
    $new_uri .= '?target=' . $self->escape_url( $r->uri() );

    return $self->_do_redirect($r, $new_uri);
}


sub _do_redirect {
    my $self = shift;
    my ($r, $new_uri) = @_;

    $r->err_header_out(Location => $new_uri);
    my $output = "Redirect: <a href=\"$new_uri\">$new_uri</a>";
    # $r->custom_response(REDIRECT, $output);

    return REDIRECT;
}


sub escape_url {
    my $self = shift;
    my ($text) = @_;

    # URL-escape string
    $text =~ s/\=/\%3d/g;
    $text =~ s/\&/\%26/g;
    $text =~ s/\?/\%3f/g;
    $text =~ s/\//\%2f/g;

    return $text;
}


1;
