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

=item Krang::Handler->init_handler

Determines which instance of Krang is being requested and calls
Krang::Conf->instance() to set it.

=item Krang::Handler->auth_handler

Checks for an auth cookie.  If one isn't found or it's not valid, a
redirect tosses you to the login app.  Otherwise, C<$ENV{REMOTE_USER}>
is set, the C<%session> is loaded and the request continues.

=item Krang::Handler->handler

Finds the appropriate CGI module to run based on the requested path.
Runs that module, unloads the C<%session> and returns.

=back

=head1 INTERFACE

None.

=cut

use Krang;
use Apache::URI;
use Apache::Constants qw(OK REDIRECT FORBIDDEN);
use Apache::Cookie;
use File::Spec::Functions qw(splitdir rel2abs catdir);
use Carp qw(croak);
use Krang::Conf qw(KrangRoot);
use HTML::Template;
use Digest::MD5 qw(md5_hex md5);
use Krang::Session qw(%session);
use Krang::Log qw(critical info debug);

# figure out the instance for the incoming request
sub init_handler ($$) {
    my ($pkg, $r) = @_;
    Krang::Conf->instance($r->dir_config('instance'));
    return OK;
}

# handles user authentication, tossing to the login app for
# authentication.  Sets up REMOTE_USER and SESSION_ID if successful.
sub auth_handler ($$) {
    my ($pkg, $r) = @_;
    my $path      = $r->parsed_uri()->path();
    my $instance  = Krang::Conf->instance();
    my $flavor    = $r->dir_config('flavor');

    # always allow access to the login app    
    if (($flavor eq 'root'     and $path =~ m!^/$instance/login!) or 
        ($flavor eq 'instance' and $path =~ m!^/login!)) {
        return OK;
    }

    my %cookies = Apache::Cookie->new($r)->parse();
    unless ($cookies{$r->auth_name}) {        
        # no cookie, redirect to login
        debug("No cookie found, redirecting to login");
        return _redirect_to_login($r, $flavor, $instance);
    }

    # validate cookie
    my %cookie = $cookies{$r->auth_name}->value;
    my $hash = md5_hex($cookie{user_id} . $cookie{instance} . 
                       $cookie{session_id} . $Krang::CGI::Login::SALT);
    if ($cookie{hash} ne $hash or $cookie{instance} ne $instance) {
        # invalid cookie, send to login
        critical("Invalid cookie found, possible breakin attempt from IP " . 
                 $r->connection->remote_ip . ".  Redirecting to login.");
        return _redirect_to_login($r, $flavor, $instance);
    }

    # setup REMOTE_USER
    $ENV{REMOTE_USER} = $cookie{user_id};

    # try to load the session, if it fails send to login.  Usually
    # this means the session is no longer there.
    eval { Krang::Session->load($cookie{session_id}); };
    if ($@) {
        # no cookie, redirect to login
        debug("Error loading session: $@");
        return _redirect_to_login($r, $flavor, $instance);
    }

    return OK;
}

sub _redirect_to_login {
    my ($r, $flavor, $instance) = @_;
    $r->headers_out->set(Location => ($flavor eq 'instance' ? 
                                      '/login' : "/$instance/login") .
                         '?target=' . $r->uri);
    return REDIRECT;
}


# content handler, finds a CGI module to call and calls it
sub handler ($$) {
    my $pkg    = shift;
    my $r      = shift;
    my $path   = $r->parsed_uri()->path();
    my $flavor = $r->dir_config('flavor');

    # find module
    my $module;
    if ($flavor eq 'instance') {
        # module is the first token on the path for instance vhosts
        ($module) = $path =~ m!^/(\w+)!;
    } else {
        # module is the second token on the path for root vhost
        ($module) = $path =~ m!^/\w+/(\w+)!;
    }

    # show an instance menu if no instance is set
    my $instance = Krang::Conf->instance();
    return $pkg->instance_menu() unless defined $instance;

    # default to the entry module (FIX)
    $module = 'element_editor' unless defined $module;

    # find the module pkg
    my $module_pkg = "Krang::CGI::" . 
      join('', map { ucfirst($_) } split('_', $module));
    croak("Unrecoginized module '$module' $module_pkg.")
      unless $module_pkg->can('new');

    # run the CGI app, catching any errors and writing them to log
    eval { $module_pkg->new()->run(); };
    my $err = $@;

    # unload the session ASAP, the client might be making another
    # request already!
    Krang::Session->unload();

    # if the page generated an error, cough it up
    critical($err), die($err) if $err;

    return OK;
}

# display a menu of available instances
sub instance_menu {
    my $pkg = shift;
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

1;
