use Test::More qw(no_plan);
use strict;
use warnings;

use File::Temp qw(tempfile);

# a basic working conf file
my $base_conf = <<CONF;
KrangUser nobody
KrangGroup nobody
ApacheAddr 127.0.0.1
ApachePort 80
HostName localhost.localdomain
EnableSiteServer 1
SiteServerAddr 127.0.0.1
SiteServerPort 8080
LogLevel 2
FTPAddress localhost
FTPPort 2121
SMTPServer localhost
FromAddress krangmailer\@localhost.com
BugzillaServer krang-services.ops.about.com/bugzilla
BugzillaEmail krang_test\@yahoo.com
BugzillaPassword shredder
BugzillaComponent 'Auto-submitted Bugs'
<Instance instance_one>
   InstanceDisplayName "Test Magazine One"
   InstanceHostName cms.test1.com
   InstanceDBName test
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

eval "use_ok('Krang::Conf')";
die $@ if $@;

# get the globals, all ways
ok(Krang::Conf->get("KrangRoot"));
ok(Krang::Conf->KrangRoot);
ok(Krang::Conf->get("ApachePort"));
ok(Krang::Conf->ApachePort);

Krang::Conf->import(qw(KrangRoot InstanceDBName ApachePort));
ok(KrangRoot());
ok(not defined InstanceDBName());
ok(ApachePort());

Krang::Conf->instance("instance_one");
is(Krang::Conf->instance, "instance_one");
ok(KrangRoot());
is(Krang::Conf->get("InstanceDBName"), "test");
is(InstanceDBName(), "test");

Krang::Conf->instance("instance_two");
is(Krang::Conf->instance, "instance_two");
ok(KrangRoot());
is(Krang::Conf->get("InstanceDBName"), "test2");
is(InstanceDBName(), "test2");


# make sure KrangUser and KrangGroup are checked
my $bad_conf = $base_conf;
$bad_conf =~ s/KrangUser nobody/KrangUser foo/;
_setup_conf($bad_conf);
eval { Krang::Conf::_load(); Krang::Conf->check() };
like($@, qr/KrangUser.*does not exist/);

$bad_conf = $base_conf;
$bad_conf =~ s/KrangGroup nobody/KrangGroup foo/;
_setup_conf($bad_conf);
eval { Krang::Conf::_load(); Krang::Conf->check() };
like($@, qr/KrangGroup.*does not exist/);

# make sure repeated InstanceDBNames are caught
$bad_conf = $base_conf;
$bad_conf .= <<CONF;
<Instance instance_thre>
   InstanceDisplayName "Test Magazine Three"
   InstanceHostName cms.test2.com
   InstanceDBName test2
   DBUser test3
   DBPass ""
   InstanceElementSet TestSet1
</Instance>
CONF
_setup_conf($bad_conf);
eval { Krang::Conf::_load(); Krang::Conf->check() };
like($@, qr/More than one instance/);

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
