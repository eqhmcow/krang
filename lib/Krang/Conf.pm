package Krang::Conf;
use strict;
use warnings;
use Sys::Hostname qw(hostname);
use Fcntl qw(:DEFAULT :flock);

# all valid configuration directives must be listed here
our @VALID_DIRECTIVES;
@VALID_DIRECTIVES = map { lc($_) } qw(
  ApacheAddr
  ApachePort
  ApacheMaxSize
  ApacheMaxUnsharedSize
  Assertions
  AvailableLanguages
  BadHelpNotify
  BadLoginCount
  BadLoginWait
  BadLoginNotify
  BrowserSpeedBoost
  BugzillaComponent
  BugzillaEmail
  BugzillaPassword
  BugzillaServer
  Charset
  ContactEmail
  ContactURL
  CustomCSS
  DefaultLanguage
  DBPass
  DBUser
  DBHost
  DBSock
  DBIgnoreVersion
  DisableScheduler
  EnableTemplateCache
  EnableBugzilla
  EnableFTP
  EnablePreviewEditor
  EnableSiteServer
  EnableSSL
  ErrorNotificationEmail
  ForceStaticBrowserCaching
  FromAddress
  FTPAddress
  FTPPort
  FTPHostName
  HostName
  InstanceApacheAddr
  InstanceApachePort
  InstanceDBName
  InstanceDisplayName
  InstanceElementSet
  InstanceHostName
  InstanceSSLCertificateFile
  InstanceSSLCertificateKeyFile
  InstanceSSLCertificateChainFile
  InstanceSSLCACertificateFile
  InstanceSSLCARevocationFile
  InstanceSSLPort
  IgnorePreviewRelatedStoryAssets
  IgnorePreviewRelatedMediaAssets
  KrangGroup
  KrangRoot
  KrangUser
  LogLevel
  MinSpareServers
  MaxSpareServers
  MaxClients
  PasswordChangeTime
  PasswordChangeCount
  PreviewSSL
  ReservedURLs
  RewriteLogLevel
  SavedVersionsPerMedia
  SavedVersionsPerStory
  SavedVersionsPerTemplate
  SchedulerDefaultFailureDelay
  SchedulerMaxChildren
  SchedulerSleepInterval
  Secret
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
  TrashMaxItems
);

our @REQUIRED_DIRECTIVES = qw(
  ApacheAddr
  ApachePort
  BugzillaComponent
  BugzillaEmail
  BugzillaPassword
  BugzillaServer
  FromAddress
  HostName
  KrangGroup
  KrangUser
  LogLevel
  Secret
  SMTPServer
);

our @REQUIRED_INSTANCE_DIRECTIVES = qw(
  DBPass
  DBUser
  InstanceDBName
  InstanceDisplayName
  InstanceElementSet
  InstanceHostName
);

our @DEPRECATED_DIRECTIVES = qw(
  ForceStaticBrowserCaching
);

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
  @things = Things;

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

Unable to find $conf_file!

Krang scripts must be run from within an installed copy of Krang,
which will have a conf/krang.conf file.  You might be trying to run a
Krang script from a Krang source directory.

CROAK

    # get the original config file into a variable so we can do some manipulation
    my $orig_conf_file = $conf_file;
    open(my $IN, '<', $conf_file) or die "Could not open file $conf_file for reading: $!";
    my $content = do { local $/; <$IN> };
    close($IN);

    # now expand any "host-name dictionaries"
    while ($content =~ /(([\s#]*)(\S+)\s+{([^}]*)}\n?)/s) {
        my ($orig, $indent, $directive, $lines, %dict) = ($1, $2, $3, $4);
        foreach my $line (split("\n", $lines)) {
            if ($line =~ /[\s#]*(\S+)\s+["']?([^\s"']+)["']?\s*/) {
                $dict{$1} = $2;
            }
        }

        my $hostname = hostname();
        my $real_val = $dict{$hostname};
        $real_val = $dict{default} unless defined $real_val;
        die "No default configured for Hostname $hostname at $directive\n" unless defined $real_val;
        $content =~ s/\Q$orig\E/$indent$directive "$real_val"\n/g if defined $real_val;
    }

    # write it out to the new file in a cooperative/locking way
    my $new_conf_file = catfile($ENV{KRANG_ROOT}, 'tmp', 'krang.conf.expanded');
    sysopen(my $OUT, $new_conf_file, O_WRONLY | O_CREAT) or die "Could not open $new_conf_file for writing: $!";
    flock($OUT, LOCK_EX) or die "Could not obtain write lock on $new_conf_file: $!";
    truncate($OUT, 0) or die "Could not truncate file $new_conf_file: $!";
    print $OUT $content;
    close($OUT);
    $conf_file = $new_conf_file;


    # load conf file into package global
    eval {
        our $CONF = Config::ApacheFormat->new(
            valid_directives => \@VALID_DIRECTIVES,
            valid_blocks     => ['instance']
        );
        $CONF->read($conf_file);
    };
    croak("Unable to read config file '$conf_file'.  Error was: $@")
      if $@;
    croak("Unable to read config file '$conf_file'.")
      unless $CONF;

    # mix in KrangRoot
    my $extra    = qq(KrangRoot "$ENV{KRANG_ROOT}"\n);
    my $extra_fh = IO::Scalar->new(\$extra);
    $CONF->read($extra_fh);
}

# load the configuration file during startup
_load();

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
    my $pkg     = shift;
    my $callpkg = caller(0);

    foreach my $name (@_) {
        no strict 'refs';    # needed for glob refs
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

sub cms_root {
    my $pkg = shift;
    my $cms_root = $ENV{HTTPS} ? 'https://' : 'http://';
    my $host_name = $pkg->get('hostname');
    my $instance_host_name = $pkg->get('instancehostname');
    if ($host_name && $host_name eq $ENV{SERVER_NAME}) {
        my $port        = $ENV{HTTPS} ? $pkg->get('sslapacheport') : $pkg->get('apacheport');
        $cms_root .= $host_name . ':' . $port . '/' . $pkg->instance();
    } elsif ($instance_host_name && $instance_host_name eq $ENV{SERVER_NAME}) {
        my $port = $ENV{HTTPS}
          ? ($pkg->get('instancesslport')    || $pkg->get('sslapacheport')) 
          : ($pkg->get('instanceapacheport') || $pkg->get('apacheport'));
        $cms_root .= $instance_host_name . ':' . $port;
    } else {
        croak __PACKAGE__ . "::cms_root() - SERVER_NAME '$ENV{SERVER_NAME}' differs from from HostName '$host_name' and InstanceHostName '$instance_host_name'";
    }

    return $cms_root;
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
    foreach my $dir (@REQUIRED_DIRECTIVES) {
        _broked("Missing required $dir directive")
          unless defined $CONF->get($dir);
    }

    # check for deprecated directives at the top level
    my %found_top_level_deprecated_directives;
    foreach my $dir (@DEPRECATED_DIRECTIVES) {
        if (defined $CONF->get($dir)) {
            warn("Directive $dir is deprecated.\n");
            $found_top_level_deprecated_directives{$dir} = 1;
        }
    }

    # make sure each instance has the necessary directives
    foreach my $instance ($pkg->instances()) {
        my $block = $CONF->block(instance => $instance);

        foreach my $dir (@REQUIRED_INSTANCE_DIRECTIVES) {
            _broked("Instance '$instance' missing required '$dir' directive\n")
              unless defined $block->get($dir);
        }

        # check to make sure that the InstanceElementSet exists.

        # using Krang::File would be easier but this module shouldn't
        # load any Krang:: modules since that will prevent them from
        # being overridden in addons via class.conf
        my $element_set = $block->get('InstanceElementSet');
        opendir(my $dir, catdir($ENV{KRANG_ROOT}, 'addons'));
        my @addons = map { catdir($ENV{KRANG_ROOT}, 'addons', $_) }
          grep { $_ !~ /^\./ and $_ ne 'CVS' } readdir($dir);

        my $found = 0;
        foreach my $libdir ($ENV{KRANG_ROOT}, @addons) {
            $found = 1, last
              if -d catdir($libdir, 'element_lib', $element_set);
        }
        _broked("Instance '$instance' is looking for InstanceElementSet "
              . "'$element_set' which is not installed")
          unless $found;

        # check for deprecated directives at the instance level
        foreach my $dir (@DEPRECATED_DIRECTIVES) {
            next if $found_top_level_deprecated_directives{$dir};
            warn("Directive $dir in Instance '$instance' is deprecated.\n")
              if defined $block->get($dir);
        }
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
            _broked("More than one instance is using the '"
                  . $block->get("InstanceDBName")
                  . "' database");
        }
        $seen{$block->get("InstanceDBName")} = 1;
    }

    # make sure that if EnableSSL is true, that we were built with-sslmonitor
    if ($CONF->get('EnableSSL')) {
        my %params = Krang::Platform->build_params();
        _broked("EnableSSL cannot be true if you did not build Krang --with-ssl")
          unless ($params{SSL});
    }
}

sub _broked {
    warn("Error found in krang.conf: $_[0].\n");
    exit(1);
}

# run the check ASAP, unless we're in upgrade mode
__PACKAGE__->check() unless ($ENV{KRANK_CONF_NOCHECK});

=back

=cut

1;
