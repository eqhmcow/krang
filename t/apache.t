use strict;
use warnings;

use Krang::Script;
use Krang::Conf qw(KrangRoot RootVirtualHost ApachePort);
use LWP::UserAgent;
use HTTP::Request::Common;
use File::Spec::Functions qw(catfile);
use HTTP::Cookies;

# skip tests unless Apache running
BEGIN {
    unless (-e catfile(KrangRoot, 'tmp', 'httpd.pid')) {
        eval "use Test::More skip_all => 'Krang Apache server not running.';";
    } else {
        eval "use Test::More qw(no_plan);"
    }
    die $@ if $@;
}

# get creds
my $username = $ENV{KRANG_USERNAME} ? $ENV{KRANG_USERNAME} : 'admin';
my $password = $ENV{KRANG_PASSWORD} ? $ENV{KRANG_PASSWORD} : 'shredder';

# determine base url
my $base_url = 'http://' . RootVirtualHost;
$base_url .= ":" . ApachePort if ApachePort ne '80';
$base_url .= '/';

# try to request the root page
my $ua = LWP::UserAgent->new(agent => 'Mozilla/5.0');

my $res = $ua->request(GET($base_url));
ok($res->is_success, "request root index page");

foreach my $instance (Krang::Conf->instances()) {
    # fresh cookie jar for this instance
    my $cookies = HTTP::Cookies->new();
    $ua->cookie_jar($cookies);

    # try hitting each instance, should get a redirect to login
    $res = $ua->request(GET "$base_url$instance/");
    ok($res->is_success);
    like($res->base->path, qr/login.pl$/, "got login page");

    # try logging in with a bad password
    $res = $ua->request(POST "$base_url$instance/login.pl",
                        [ rm => 'login',
                          username => rand() ,
                          password => rand() ]);
    my $count = 0;
    $cookies->scan(sub { $count++ });
    is($count, 0, "didn't get a cookie, login failed as expected");

    # try logging in with good creds
    $res = $ua->request(POST "$base_url$instance/login.pl",
                        [ rm => 'login',
                          username => $username ,
                          password => $password]);
    $count = 0;
    $cookies->scan(sub { $count++ });
    is($count, 1, "got a cookie, login success");

}

