use Test::More qw(no_plan);

use strict;
use warnings;
use Krang::Conf qw(KrangRoot FTPPort FTPAddress);
use Krang::Session qw(%session);
use Krang::Script;
use Krang::Category;
use Krang::Site;
use Krang::User;
use Krang::Media;
use Krang::Session qw(%session);
use Net::FTP;
use IPC::Run qw(start);
use File::Spec::Functions qw(catfile);
use IO::Scalar;

my ($in,$out);
my @cmd = (catfile(KrangRoot,'bin','krang_ftpd'), '-s');
my $server_run = start (\@cmd, \$in, \$out, \$out );

# wait 3 seconds for the server to have time to start
sleep 3;

# set up end block to kill server at the end
END {
    $server_run->kill_kill;
}


my @sites;

# create a site and some categories to put stories in
$sites[0] = Krang::Site->new(preview_url  => 'preview.test.com',
                            url          => 'test.com',
                            publish_path => '/tmp/test_publish',
                            preview_path => '/tmp/test_preview');
isa_ok($sites[0], 'Krang::Site', 'is Krang::Site');
$sites[0]->save();

my ($root_cat) = Krang::Category->find(site_id => $sites[0]->site_id, dir => "/");
isa_ok($root_cat, 'Krang::Category', 'is Krang::Category');
$root_cat->save();

my @cat;
for (0 .. 10) {
    push @cat, Krang::Category->new(site_id   => $sites[0]->site_id,
                                    parent_id => $root_cat->category_id,
                                    dir       => 'test_' . $_);
    isa_ok($root_cat, 'Krang::Category', 'is Krang::Category');
    $cat[-1]->save();
}

# create a site and some categories to put stories in
$sites[1] = Krang::Site->new(preview_url  => 'preview.test2.com',
                            url          => 'test2.com',
                            publish_path => '/tmp/test2_publish',
                            preview_path => '/tmp/test2_preview');
isa_ok($sites[1], 'Krang::Site', 'is Krang::Site');
$sites[1]->save();

my ($root_cat2) = Krang::Category->find(site_id => $sites[1]->site_id, dir => "/");
isa_ok($root_cat2, 'Krang::Category', 'is Krang::Category');
$root_cat2->save();

my @cat2;
for (0 .. 10) {
    push @cat2, Krang::Category->new(site_id   => $sites[1]->site_id,
                                    parent_id => $root_cat2->category_id,
                                    dir       => 'test2_' . $_);
    isa_ok($root_cat2, 'Krang::Category', 'is Krang::Category');
    $cat2[-1]->save();
}

# set up for cleanup 
END {
    $_->delete for @cat;
    $_->delete for @cat2;
    $_->delete for @sites;
}

# set up Net::FTP session
my $ftp = Net::FTP->new(FTPAddress, Port => FTPPort);

# set up end block to kill server at end
END {
    $ftp->quit;
}

isa_ok($ftp, 'Net::FTP', 'is Net::FTP');

my ($username, $password);

$username = $ENV{KRANG_USERNAME} ? $ENV{KRANG_USERNAME} : 'admin';
$password = $ENV{KRANG_PASSWORD} ? $ENV{KRANG_PASSWORD} : 'shredder';

is( $ftp->login( $username, $password ), '1', 'Login Test' );

my @auth_instances;
my @instances = Krang::Conf->instances();
foreach my $instance (@instances) {

    # set instance
    Krang::Conf->instance($instance);

    my $login_ok = Krang::User->check_auth($username,$password);

    if ($login_ok) {
       push @auth_instances, $instance;
    }        
}

Krang::Conf->instance($instances[0]);

my @listed_instances = $ftp->ls();

is ("@listed_instances", "@auth_instances", "FTPServer returned instances");

$ftp->cwd($instances[0]);

my @types = qw(media template);
my @ret_types = $ftp->ls();
is("@ret_types", "@types", "Type listing");

my @found_sites = Krang::Site->find(order_by => 'url');

my $sitenames = join(" ",(map { $_->url } @found_sites));

# go into media then templates and test
foreach my $type (@types) {
    $ftp->cwd($type);
    my @ret_sites = $ftp->ls();
    is("@ret_sites", $sitenames, "Site listing in $type");

    foreach my $site (@ret_sites) {
        $ftp->cwd($site);
        my @site_obj = Krang::Site->find(url => $site);
        isa_ok($site_obj[0], 'Krang::Site', "Krang::Site $site");
        my ($rc) = Krang::Category->find(site_id => $site_obj[0]->site_id, dir => "/");
        isa_ok($rc, 'Krang::Category', "Krang::Category");

        my @cat_list = Krang::Category->find(site_id => $site_obj[0]->site_id, parent_id => $rc->category_id);
        my $catnames = join(" ",(map { $_->dir } @cat_list));

        my $list_string;

        if ($type eq 'media') {
            my @existing_media = Krang::Media->find( category_id => $rc->category_id );
            my $medianames = join(" ",(map { $_->filename } @existing_media));

            if ($catnames) {
                $list_string = $catnames;
                $list_string .= " $medianames" if $medianames;
            } elsif ($medianames) {
                $list_string = $medianames; 
            }
        } else {
            my @existing_templates = Krang::Template->find( category_id => $rc->category_id );

            my $tnames = join(" ",(map { $_->filename } @existing_templates));
            
            if ($catnames) {
                $list_string = $catnames;
                $list_string .= " $tnames" if $tnames;
            } elsif ($tnames) {
                $list_string = $tnames; 
            }
        }
 
        my @ret_cats = $ftp->ls();
        is("@ret_cats", $list_string, "Category ls in site $site for type $type");
       
        # go into each category and create, get, put, delete media/template
        foreach my $cat (@cat_list) {
            my $cat_dir = $cat->dir;
            $ftp->cwd($cat_dir);
            $ftp->binary;
            if ($type eq 'media') {
                my $media_path = catfile(KrangRoot, 't','media','krang.jpg');
                is($ftp->put($media_path), 'krang.jpg', "Put media krang.jpg in category $cat_dir" );
                is($ftp->put($media_path), 'krang.jpg', "Put version 2 of media krang.jpg in category $cat_dir" ); 
                is($ftp->delete('krang.jpg'), 1, "Delete media krang.jpg in category $cat_dir");
            } else {
                my $template_path = catfile(KrangRoot, 't','template','test.tmpl');
                is($ftp->put( $template_path ), 'test.tmpl', "Put template test.tmpl in category $cat_dir" );
                is($ftp->delete('test.tmpl'), 1, "Delete template test.tmpl in category $cat_dir");
            }
            $ftp->cdup()            
        }
        # back to site listings 
        $ftp->cdup();
    }
    # back into type level 
    $ftp->cdup();
}
