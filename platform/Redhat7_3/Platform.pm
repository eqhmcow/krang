package Redhat7_3::Platform;
use strict;
use warnings;

use base 'Krang::Platform';

use Cwd qw(cwd);

sub guess_platform {
    return 0 unless -e '/etc/redhat-release';
    open(RELEASE, '/etc/redhat-release') or return 0;
    my $release = <RELEASE>;
    close RELEASE;
    return 1 if $release =~ /Red Hat Linux release 7/;
    return 0;
}

# setup init script so Krang starts on boot
sub finish_installation {
    my ($pkg, %arg) = @_;
    my %options = %{$arg{options}};

    my $init_script = "krang-". $options{HostName} .".init";    
    print "Installing Krang init.d script '$init_script'\n";

    my $old = cwd;
    chdir("/etc/init.d");

    my $InstallPath =  $options{InstallPath};
    unlink $init_script if -e $init_script;
    my $link_init = "ln -s $InstallPath/bin/krang_ctl $init_script";
    system($link_init) && die ("Can't link init script: $!");

    print "Setting $init_script to start on boot\n";
    my $chkconfig = "chkconfig --add $init_script";
    system($chkconfig) && die("Can't chkconfig --add $init_script: $!");

    $chkconfig = "chkconfig $init_script on";
    system($chkconfig) && die("Can't chkconfig $init_script on: $!");

    chdir $old;
}


1;
