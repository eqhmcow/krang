use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;

use File::Spec::Functions qw(catfile);
use File::Temp qw(tempfile);

# get creds
my $username = $ENV{KRANG_USERNAME} ? $ENV{KRANG_USERNAME} : 'admin';
my $password = $ENV{KRANG_PASSWORD} ? $ENV{KRANG_PASSWORD} : 'whale';

# a basic working conf file
my $base_conf = <<CONF;
KrangUser nobody
KrangGroup nobody
ApacheAddr 127.0.0.1
ApachePort 80
ApacheSSLPort 443
HostName krang_ssltest
LogLevel 2
FTPAddress 127.0.0.1
FTPHostName localhost
FTPPort 2121
SMTPServer localhost
FromAddress krangmailer\@localhost.com
BugzillaServer krang-services.ops.about.com/bugzilla
BugzillaEmail krang_test\@yahoo.com
BugzillaPassword whale
BugzillaComponent 'Auto-submitted Bugs'
SSLEngine on
SSLPassPhraseDialog  builtin
SSLSessionCacheTimeout  3600
SSLRandomSeedStartup builtin
SSLRandomSeedConnect builtin
SSLRandomSeed builtin
SSLProtocol  "all -SSLv2"
SSLCipherSuite  "ALL:!ADH:!EXPORT56:RC4+RSA:+HIGH:+MEDIUM:+LOW:+SSLv2:+EXP:+eNULL"
SSLVerifyClient  none
SSLVerifyDepth   1
SetEnvIf "User-Agent \".*MSIE.*\" nokeepalive ssl-unclean-shutdown downgrade-1.0 force-response-1.0"
SSLOptions  "+StdEnvVars"
SSLLogLevel  info
<Instance instance_one>
   InstanceDisplayName "Test Magazine One"
   InstanceHostName cms.test1.com
   InstanceHostIPAddress 127.0.0.1
   InstanceHostPort 8080
   InstanceHostSSLPort 8443
   InstanceDBName test
   DBUser test
   DBPass ""
   InstanceElementSet TestSet1
   SSLEngine on
   SSLProtocol  "all"
   SSLCipherSuite  "ALL:!ADH:!EXPORT56:RC4+RSA:+HIGH:+MEDIUM:+LOW:+SSLv2:+EXP"
   SSLVerifyClient  optional
   SSLVerifyDepth   10
   SSLLogLevel      trace
</Instance>
<Instance instance_two>
   InstanceDisplayName "Test Magazine Two"
   InstanceHostName cms.test2.com
   InstanceHostIPAddress 127.0.0.1
   InstanceHostPort 8081
   InstanceHostSSLPort 8444
   SSLEngine on
   InstanceDBName test2
   DBUser test2
   DBPass ""
   InstanceElementSet TestSet1
   SSLEngine on
   SSLProtocol      'all -SSLv3'
   SSLCipherSuite   'RSA'
   SSLVerifyClient  require
   SSLVerifyDepth   20
   SSLLogLevel      error
</Instance>
CONF

# setup the test conf file
_setup_conf($base_conf);

eval "use_ok(pkg('Conf'))";
die $@ if $@;

# get the globals, all ways
ok(pkg('Conf')->get('ApacheSSLPort'), "ApacheSSLPort directive");
ok(pkg('Conf')->ApacheSSLPort, "ApacheSSLPort directive");
ok(pkg('Conf')->get('SSLEngine'), "SSLEngine directive");
ok(pkg('Conf')->SSLEngine, "SSLEngine directive");
ok(pkg('Conf')->get('SSLPassPhraseDialog'), "SSLPassPhraseDialog directive");
ok(pkg('Conf')->SSLPassPhraseDialog, "SSLPassPhraseDialog directive");
ok(pkg('Conf')->get('SSLRandomSeed'), "SSLRandomSeed directive");
ok(pkg('Conf')->SSLRandomSeed, "SSLRandomSeed directive");
ok(pkg('Conf')->get('SSLRandomSeedStartup'), "SSLRandomSeedStartup directive");
ok(pkg('Conf')->SSLRandomSeedStartup, "SSLRandomSeedStartup directive");
ok(pkg('Conf')->get('SSLRandomSeedConnect'), "SSLRandomSeedConnect directive");
ok(pkg('Conf')->SSLRandomSeedConnect, "SSLRandomSeedConnect directive");
ok(pkg('Conf')->get('SSLProtocol'), "SSLProtocol directive");
ok(pkg('Conf')->SSLProtocol, "SSLProtocol directive");
ok(pkg('Conf')->get('SSLCipherSuite'), "SSLCipherSuite directive");
ok(pkg('Conf')->SSLCipherSuite, "SSLCipherSuite directive");
ok(pkg('Conf')->get('SSLVerifyClient'), "SSLVerifyClient directive");
ok(pkg('Conf')->SSLVerifyClient, "SSLVerifyClient directive");
ok(pkg('Conf')->get('SSLVerifyDepth'), "SSLVerifyDepth directive");
ok(pkg('Conf')->SSLVerifyDepth, "SSLVerifyDepth directive");
ok(pkg('Conf')->get('SetEnvIf'), "SetEnvIf directive");
ok(pkg('Conf')->SetEnvIf, "SetEnvIf directive");
ok(pkg('Conf')->get('SSLOptions'), "SSLOptions directive");
ok(pkg('Conf')->SSLOptions, "SSLOptions directive");
ok(pkg('Conf')->get('SSLLogLevel'), "SSLLogLevel directive");
ok(pkg('Conf')->SSLLogLevel, "SSLLogLevel directive");

pkg('Conf')->import(qw(ApacheSSLPort InstanceHostIPAddress      InstanceHostPort InstanceHostSSLPort
                       SSLEngine     SSLProtocol SSLCipherSuite SSLVerifyClient  SSLVerifyDepth
                       SSLLogLevel   KrangRoot));
ok(ApacheSSLPort(), "ApacheSSLPort");
ok(!defined(InstanceHostIPAddress()), "InstanceHostIPAddress");
ok(!defined(InstanceHostPort()), "InstanceHostPort");
ok(!defined(InstanceHostSSLPort()), "InstanceHostSSLPort");

pkg('Conf')->instance("instance_one");
is(pkg('Conf')->instance, "instance_one", "Verifying first instance");
is(InstanceHostIPAddress(), '127.0.0.1', "InstanceHostIPAddress");
is(InstanceHostPort(), '8080', "InstanceHostPort");
is(InstanceHostSSLPort(), '8443', "InstanceHostSSLPort");
is(SSLEngine(), 'on', "SSLEngine");
is(SSLProtocol(), 'all', "SSLProtocol");
is(SSLCipherSuite(), "ALL:!ADH:!EXPORT56:RC4+RSA:+HIGH:+MEDIUM:+LOW:+SSLv2:+EXP", "SSLCipherSuite");
is(SSLVerifyClient(), 'optional', "SSLVerifyClient");
is(SSLVerifyDepth(), '10', "SSLVerifyDepth");
is(SSLLogLevel(), 'trace', "SSLLogLevel");

pkg('Conf')->instance("instance_two"); 
is(pkg('Conf')->instance, "instance_two", "Verifying second instance");
is(InstanceHostIPAddress(), '127.0.0.1', "InstanceHostIPAddress");
is(InstanceHostPort(), '8081', "InstanceHostPort");
is(InstanceHostSSLPort(), '8444', "InstanceHostSSLPort");
is(SSLEngine(), 'on', "SSLEngine");
is(SSLProtocol(), 'all -SSLv3', "SSLProtocol");
is(SSLCipherSuite(), 'RSA', "SSLCipherSuite");
is(SSLVerifyClient(), 'require', "SSLVerifyClient");
is(SSLVerifyDepth(), '20', "SSLVerifyDepth");
is(SSLLogLevel(), 'error', "SSLLogLevel");


# put an arbitary conf file into place so that Krang::Conf will load it
sub _setup_conf {
    my $conf = shift;
    open(CONF, ">tmp/test.conf") or die $!;
    print CONF $conf;
    close(CONF);

    # use this file as krang.conf
    $ENV{KRANG_CONF} = "tmp/test.conf";
}

END { unlink("tmp/test.conf") }
