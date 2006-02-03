use Krang::ClassFactory qw(pkg);
use Test::More (tests => 31);
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
EnableSSL 1
SSLApachePort 443
SSLPassPhraseDialog  builtin
SSLSessionCacheTimeout  3600
SSLRandomSeedStartup builtin
SSLRandomSeedConnect builtin
SSLProtocol  "all -SSLv2"
SSLCipherSuite  "ALL:!ADH:!EXPORT56:RC4+RSA:+HIGH:+MEDIUM:+LOW:+SSLv2:+EXP:+eNULL"
SSLVerifyClient  none
SSLVerifyDepth   1
SSLLogLevel  info
<Instance instance_one>
   InstanceDisplayName "Test Magazine One"
   InstanceHostName cms.test1.com
   InstanceDBName test1
   DBUser test
   DBPass ""
   InstanceElementSet TestSet1
</Instance>
<Instance instance_two>
   InstanceDisplayName "Test Magazine Two"
   InstanceHostName cms.test2.com
   InstanceDBName test2
   DBUser test2
   DBPass ""
   InstanceElementSet TestSet1
</Instance>
CONF

# setup the test conf file
_setup_conf($base_conf);

eval "use_ok(pkg('Conf'))";
die $@ if $@;

# get the globals, all ways
my @ssl_directives = qw(
    SSLApachePort EnableSSL SSLPassPhraseDialog SSLRandomSeedStartup 
    SSLRandomSeedConnect SSLProtocol SSLCipherSuite SSLVerifyClient 
    SSLVerifyDepth SSLLogLevel
);

foreach my $directive (@ssl_directives) {
    ok(pkg('Conf')->get($directive), "$directive get()");
    ok(pkg('Conf')->$directive, "$directive as method");
    pkg('Conf')->import($directive);
    ok(eval "$directive()", "$directive imported");
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
