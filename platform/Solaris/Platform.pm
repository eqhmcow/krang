package Solaris::Platform;
use strict;
use warnings;

use base 'Krang::Platform';
use Cwd qw(cwd);

sub guess_platform {
    my $release = `uname -a`;

    return 1 if $release =~ /SunOS\ \w+\ 5\.\d/;
    return 0;
}

# Solaris ifconfig has slightly different syntax.
sub check_ip {
    my ($pkg, %arg) = @_;
    my $IPAddress = $arg{ip};

    my $ifconfig = `/sbin/ifconfig -a`;
    my @ip_addrs = ();
    foreach my $if_line (split(/\n/, $ifconfig)) {
        next unless ($if_line =~ /inet\ (\d+\.\d+\.\d+\.\d+)/);
        my $ip = $1;
        push(@ip_addrs, $ip);
    }
    unless (grep {$_ eq $IPAddress} @ip_addrs) {
        return 0;
    }
    return 1;
}

# Solaris creates groups differently as well.
sub create_krang_group {
    my ($pkg, %args) = @_;

    my %options = %{$args{options}};
    my $KrangGroup  = $options{KrangGroup};

    my $groupadd_bin = $pkg->find_bin(bin => 'groupadd');

    print "Creating UNIX group ('$KrangGroup')\n";
    my ($gname,$gpasswd,$gid,$gmembers) = getgrnam($KrangGroup);

    unless (defined($gid)) {
        my $groupadd = $groupadd_bin;
        $groupadd .= " $KrangGroup";
        system($groupadd) && die("Can't add group: $!");

        ($gname,$gpasswd,$gid,$gmembers) = getgrnam($KrangGroup);
        print "  Group created (gid $gid).\n";

    } else {
        print "  Group already exists (gid $gid).\n";
    }

    return $gid;
}

# Solaris also creates users in a different fashion.
sub create_krang_user {
    my %options = %{$args{options}};

    my $useradd_bin = $pkg->find_bin(bin => 'useradd');

    my $KrangUser   = $options{KrangUser};
    my $KrangGroup  = $options{KrangGroup};
    my $InstallPath = $options{InstallPath};

    # Get KrangGroup info.
    my ($gname,$gpasswd,$gid,$gmembers) = getgrnam($KrangGroup);

    # Create user, if necessary
    print "Creating UNIX user ('$KrangUser')\n";
    my ($uname,$upasswd,$uid,$ugid,$uquota,$ucomment,$ugcos,$udir,$ushell,$uexpire) = getpwnam($KrangUser);

    unless (defined($uid)) {
        my $useradd = $useradd_bin;

        $useradd .= " -d $InstallPath -g $gid -c 'Krang User' $KrangUser";
        system($useradd) && die("Can't add user: $!");

        # Update user data
        ($uname,$upasswd,$uid,$ugid,$uquota,$ucomment,$ugcos,$udir,$ushell,$uexpire) = getpwnam($KrangUser);
        print "  User created (uid $uid).\n";
    } else {
        print "  User already exists (uid $uid).\n";
    }

    # Sanity check - make sure the user is a member of the group.
    ($gname,$gpasswd,$gid,$gmembers) = getgrnam($KrangGroup);

    my @group_members = ( split(/\s+/, $gmembers) );
    my $user_is_group_member = ( grep { $_ eq $KrangUser } @group_members );

    unless (($ugid eq $gid) or $user_is_group_member) {
        $pkg->krang_usermod(options => \%options);
    }

    return $uid;
}

# Solaris usermod is different as well.
sub krang_usermod {
    my ($pkg, %args) = @_;

    my %options = %{$args{options}};

    my $KrangUser  = $options{KrangUser};
    my $KrangGroup = $options{KrangGroup};

    print "  Adding user $KrangUser to group $KrangGroup.\n";

    my $usermod = $pkg->find_bin(bin => 'pw');

    $usermod .= " usermod $KrangUser -G $KrangGroup ";

    system($usermod) && die("Can't add user $KrangUser to group $KrangGroup: $!");
    print "  User added to group.\n";
}

# setup init script in /etc/rc.d.
sub finish_installation {
    my ($pkg, %arg) = @_;
    my %options = %{$arg{options}};

    my $init_script = "krang-". $options{HostName};
    print "Installing Krang init script '$init_script'\n";

    my $old = cwd;
    chdir("/etc/rc.d");

    my $InstallPath = $options{InstallPath};
    unlink $init_script if -e $init_script;
    my $link_init = "ln -s $InstallPath/bin/krang_ctl $init_script";
    system($link_init) && die ("Can't link init script: $!");

    chdir $old;
}

sub post_install_message {
    my ($pkg, %arg) = @_;
    my %options = %{$arg{options}};

    $pkg->SUPER::post_install_message(%arg);

    my $init_script = "krang-" . $options{HostName};

    # return a note about setting up krang_ctl on boot.
    print "   Krang has installed a control script in: /etc/rc.d/$init_script\n\n";
}

1;
