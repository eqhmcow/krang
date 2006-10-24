package Krang::Conf;
use strict;
use warnings;

# all valid configuration directives must be listed here
our @VALID_DIRECTIVES;
BEGIN {
@VALID_DIRECTIVES = map { lc($_) } qw(
ApacheAddr
ApachePort
Assertions
BadLoginCount
BadLoginWait
BugzillaComponent
BugzillaEmail
BugzillaPassword
BugzillaServer
Charset
DBPass
DBUser
DBHost
DBSock
EnableBugzilla
EnableSiteServer
EnableSSL
FromAddress
FTPAddress
FTPPort
FTPHostName
HostName
InstanceDBName
InstanceDisplayName
InstanceElementSet
InstanceHostName
KrangGroup
KrangRoot
KrangUser
LogLevel
SchedulerMaxChildren
SiteServerAddr
SiteServerPort
SMTPServer
Skin
SSLApachePort
SSLPassPhraseDialog
SSLRandomSeedStartup
SSLRandomSeedConnect
SSLSessionCacheTimeout
SSLProtocol
SSLCipherSuite
SSLVerifyClient
SSLVerifyDepth
SSLLogLevel
);
}

use Krang::Platform;
use File::Spec::Functions qw(catfile catdir rel2abs);
use Carp qw(croak);
use Config::ApacheFormat;
use Cwd qw(fastcwd);
use IO::Scalar;

=head1 NAME

Krang::Conf - Krang configuration module

=head1 SYNOPSIS

  # all configuration directives are available as exported subs
  use Krang::ClassLoader Conf => qw(KrangRoot Things);
  $root = KrangRoot;
  @thinks = Things;

  # you can also call get() in Krang::Conf directly
  $root = pkg('Conf')->get("KrangRoot");

  # or you can access them as methods in the Krang::Conf module
  $root = pkg('Conf')->rootdir;

  # the current instance, which affects the values returned, can
  # manipulated with instance():
  pkg('Conf')->instance("this_instance");

  # get a list of available instances
  @instances = pkg('Conf')->instances();

=head1 DESCRIPTION

This module provides access to the configuration settings in
F<krang.conf>.  The routines provided will return the correct settings
based on the currently active instance, accesible and setable using
C<< Krang::Conf->instance() >>.

Full details on all configuration parameters is available in the
configuration document, which you can find at:

  http://krang.sourceforge.net/docs/configuration.html

=cut

# package variables
our $CONF;
our $INSTANCE;
our $INSTANCE_CONF;

# internal routine to load the conf file.  Called by a BEGIN during
# startup, and used during testing.
sub _load {
    # find a default conf file
    my $conf_file;
    if (exists $ENV{KRANG_CONF}) {
        $conf_file = $ENV{KRANG_CONF};
    } else { 
        $conf_file = catfile($ENV{KRANG_ROOT}, "conf", "krang.conf");
    }

    croak(<<CROAK) unless -e $conf_file and -r _;

Unable to find krang.conf!

Krang scripts must be run from within an installed copy of Krang,
which will have a conf/krang.conf file.  You might be trying to run a
Krang script from a Krang source directory.

CROAK

    # load conf file into package global
    eval {
        our $CONF = Config::ApacheFormat->new(valid_directives => 
                                              \@VALID_DIRECTIVES,
                                              valid_blocks => [ 'instance' ]);
        $CONF->read($conf_file);
    };
    croak("Unable to read config file '$conf_file'.  Error was: $@")
      if $@;
    croak("Unable to read config file '$conf_file'.")
      unless $CONF;

    # mix in KrangRoot
    my $extra = qq(KrangRoot "$ENV{KRANG_ROOT}"\n);
    my $extra_fh = IO::Scalar->new(\$extra);
    $CONF->read($extra_fh);
}

# load the configuration file during startup
BEGIN { _load(); }

=head1 INTERFACE

=over 4

=item C<< $value = Krang::Conf->get("DirectiveName") >>

=item C<< @values = Krang::Conf->get("DirectiveName") >>

Returns the value of a configuration directive.  Directive names are
case-insensitive.

=cut

sub get {
    return $INSTANCE_CONF->get($_[1]) if $INSTANCE_CONF;
    return $CONF->get($_[1]);
}

=item C<< $value = Krang::Conf->directivenamehere() >>

=item C<< @values = Krang::Conf->directivenamehere() >>

Gets the value of a directive using an autoloaded method.
Case-insensitive.

=cut

sub AUTOLOAD {
    our $AUTOLOAD;
    return if $AUTOLOAD =~ /DESTROY$/;
    my ($name) = $AUTOLOAD =~ /([^:]+)$/;

    return shift->get($name);
}

=item C<< $value = ExportedDirectiveName() >>

=item C<< @values = ExportedDirectiveName() >>

Gets the value of a variable using an exported, autoloaded method.
Case-insensitive.

=cut

# export config getters on demand
sub import {
    my $pkg = shift;
    my $callpkg = caller(0);
    
    foreach my $name (@_) {
        no strict 'refs'; # needed for glob refs
        *{"$callpkg\::$name"} = sub () { $pkg->get($name) };
    } 
}

=item C<< $current_instance = Krang::Conf->instance() >>

=item C<< Krang::Conf->instance("instance name") >>

Gets or sets the currently active instance.  After setting the active
instance, all requests for variables will retrieve values specific to
this instance.

Before the first call to C<instance()> only globally declared variables
are available.  Setting the instance to C<undef> will recreate this
state.

=cut

sub instance {
    my $pkg = shift;
    return $INSTANCE unless @_;
    
    my $instance = shift;
    if (defined $instance) {
        # get a handle on the block
        my $block;
        eval { $block = $CONF->block(instance => $instance); };
        die("Requested instance '$instance' does not exist in krang.conf.\n\n")
          unless $block;

        # setup package state
        $INSTANCE      = $instance;
        $INSTANCE_CONF = $block;
    } else {
        # clear state
        undef $INSTANCE;
        undef $INSTANCE_CONF;
    }

    return $INSTANCE;
}   

=item C<< @instances = Krang::Conf->instances() >>

Returns a list of available instances.

=cut

sub instances {
    my @instances = $CONF->get("Instance");
    return map { $_->[1] } @instances;
}

=item C<< Krang::Conf->check() >>

Sanity-check Krang configuration.  This will die() with an error
message if something is wrong with the configuration file.

This is run when the Krang::Conf loads unless the environment variable
"KRANK_CONF_NOCHECK" is set to a true value.

=cut

sub check {
    my $pkg = shift;

    # check required directives
    foreach my $dir (qw(KrangUser KrangGroup ApacheAddr ApachePort
                        HostName LogLevel FTPPort FTPHostName FTPAddress
                        SMTPServer FromAddress BugzillaEmail BugzillaServer
                        BugzillaPassword BugzillaComponent)) {
        _broked("Missing required $dir directive") 
          unless defined $CONF->get($dir);
    }

    # make sure each instance has the necessary directives
    foreach my $instance ($pkg->instances()) {
        my $block = $CONF->block(instance => $instance);

        foreach my $dir (qw(InstanceHostName InstanceElementSet InstanceDisplayName
                            InstanceDBName DBPass DBUser)) {
            _broked("Instance '$instance' missing required '$dir' directive")
              unless defined $block->get($dir);
        }

        # check to make sure that the InstanceElementSet exists.

        # using Krang::File would be easier but this module shouldn't
        # load any Krang:: modules since that will prevent them from
        # being overridden in addons via class.conf
        my $element_set = $block->get('InstanceElementSet');
        opendir(my $dir, catdir($ENV{KRANG_ROOT}, 'addons'));
        my @addons = map  { catdir($ENV{KRANG_ROOT}, 'addons', $_) }
                     grep { $_ !~ /^\./ and $_ ne 'CVS' } 
                     readdir($dir);

        my $found = 0;
        foreach my $libdir ($ENV{KRANG_ROOT}, @addons) {
            $found = 1, last
              if -d catdir($libdir, 'element_lib', $element_set);
        }
        _broked("Instance '$instance' is looking for InstanceElementSet ".
                "'$element_set' which is not installed") unless $found;
    }

    # make sure KrangUser and KrangGroup exist
    _broked("KrangUser '" . $CONF->get("KrangUser") . "' does not exist") 
      unless getpwnam($CONF->get("KrangUser"));
    _broked("KrangGroup '" . $CONF->get("KrangGroup") . "' does not exist") 
      unless getgrnam($CONF->get("KrangGroup"));

    # make sure all instances have their own DB
    my %seen;
    foreach my $instance ($pkg->instances()) {
        my $block = $CONF->block(instance => $instance);
        if ($seen{$block->get("InstanceDBName")}) {
            _broked("More than one instance is using the '" . 
                    $block->get("InstanceDBName") . "' database");
        }
        $seen{$block->get("InstanceDBName")} = 1;
    }

    # make sure that if EnableSSL is true, that we were built with-sslmonitor
    if( $CONF->get('EnableSSL') ) {
        my %params = Krang::Platform->build_params();
        _broked("EnableSSL cannot be true if you did not build Krang --with-ssl")
            unless( $params{SSL} );
    }
}

sub _broked {
    warn("Error found in krang.conf: $_[0].\n");
    exit(1);
}
 
# run the check ASAP, unless we're in upgrade mode
BEGIN { __PACKAGE__->check() unless ($ENV{KRANK_CONF_NOCHECK}) }

=back

=cut


1;
