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
EnableSiteServer 1
SiteServerAddr 127.0.0.1
SiteServerPort 8080
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
ok(pkg('Conf')->get('ApacheSSLPort'));
ok(pkg('Conf')->ApacheSSLPort);
ok(pkg('Conf')->get('SSLEngine'));
ok(pkg('Conf')->SSLEngine);
ok(pkg('Conf')->get('SSLPassPhraseDialog'));
ok(pkg('Conf')->SSLPassPhraseDialog);
ok(pkg('Conf')->get('SSLRandomSeed'));
ok(pkg('Conf')->SSLRandomSeed);
ok(pkg('Conf')->get('SSLRandomSeedStartup'));
ok(pkg('Conf')->SSLRandomSeedStartup);
ok(pkg('Conf')->get('SSLRandomSeedConnect'));
ok(pkg('Conf')->SSLRandomSeedConnect);
ok(pkg('Conf')->get('SSLProtocol'));
ok(pkg('Conf')->SSLProtocol);
ok(pkg('Conf')->get('SSLCipherSuite'));
ok(pkg('Conf')->SSLCipherSuite);
ok(pkg('Conf')->get('SSLVerifyClient'));
ok(pkg('Conf')->SSLVerifyClient);
ok(pkg('Conf')->get('SSLVerifyDepth'));
ok(pkg('Conf')->SSLVerifyDepth);
ok(pkg('Conf')->get('SetEnvIf'));
ok(pkg('Conf')->SetEnvIf);
ok(pkg('Conf')->get('SSLOptions'));
ok(pkg('Conf')->SSLOptions);
ok(pkg('Conf')->get('SSLLogLevel'));
ok(pkg('Conf')->SSLLogLevel);

pkg('Conf')->import(qw(ApacheSSLPort InstanceHostIPAddress      InstanceHostPort InstanceHostSSLPort
                       SSLEngine     SSLProtocol SSLCipherSuite SSLVerifyClient  SSLVerifyDepth
                       SSLLogLevel   KrangRoot));
ok(ApacheSSLPort());
ok(not defined InstanceHostIPAddress());
ok(not defined InstanceHostPort());
ok(not defined InstanceHostSSLPort());

pkg('Conf')->instance("instance_one");
is(pkg('Conf')->instance, "instance_one");
is(InstanceHostIPAddress(), '127.0.0.1');
is(InstanceHostPort(), '8080');
is(InstanceHostSSLPort(), '8443');
is(SSLEngine(), 'on');
is(SSLProtocol(), 'all');
is(SSLCipherSuite(), "ALL:!ADH:!EXPORT56:RC4+RSA:+HIGH:+MEDIUM:+LOW:+SSLv2:+EXP");
is(SSLVerifyClient(), 'optional');
is(SSLVerifyDepth(), '10');
is(SSLLogLevel(), 'trace');

pkg('Conf')->instance("instance_two");
is(pkg('Conf')->instance, "instance_two");
is(InstanceHostIPAddress(), '127.0.0.1');
is(InstanceHostPort(), '8081');
is(InstanceHostSSLPort(), '8444');
is(SSLEngine(), 'on');
is(SSLProtocol(), 'all -SSLv3');
is(SSLCipherSuite(), 'RSA');
is(SSLVerifyClient(), 'require');
is(SSLVerifyDepth(), '20');
is(SSLLogLevel(), 'error');

unshift @INC, catfile(KrangRoot(), 'lib');
require 'Krang/Test/Apache.pm';
import Krang::Test::Apache qw(login_ok login_not_ok request_ok get_response
                              response_like response_unlike);

foreach my $instance (pkg('Conf')->instances()) {
    pkg('Conf')->instance($instance);

    # try logging in with a bad password
    login_not_ok(rand(), rand());
    
    # try logging in with good creds
    login_ok($username, $password);
}





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
