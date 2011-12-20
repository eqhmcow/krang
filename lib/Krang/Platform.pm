package Krang::Platform;
use strict;
use warnings;

use File::Spec::Functions qw(catdir catfile canonpath);
use Cwd qw(cwd);
use Config;
use Devel::CheckLib qw(assert_lib);
my $DEBUG = 0;

=head1 NAME

Krang::Platform - base class for platform build modules

=head1 SYNOPSIS

  package Redhat9::Platform;
  use base 'Krang::Platform';

=head1 DESCRIPTION

This module serves as a base class for the platform build modules
which build help Krang binary distributions.  See
F<docs/build_tech_spec.pod> for details about how the build system
works.

=head1 INTERFACE

This module is meant to be used as a base class, so the interface
consists of methods which may be overridden.  All these methods have a
reasonable default behavior.

All methods are called as class methods.  Platform modules are free to
use package variables to hold information between calls.

=over

=item C<verify_dependencies(mode => $mode)>

Makes sure all required dependencies are in place before starting the
build, and before beginning installation.  The C<mode> parameter will
be either "build" or "install" depending on when the method is called.

This method should either succeed or die() with a message for the
user.

By default, shared object (.so) files are searched for in $Config{libpth}.
header files (.h) are search for in $Config{usrinc}, /include and /usr/local/include


The default implementation runs the following default checks (which
are all overrideable):

=over

=cut

sub verify_dependencies {

    my ($pkg, %arg) = @_;
    my $mode = $arg{mode};
    my @PATH = split(':', ($ENV{PATH} || ""));

    # check perl
    $pkg->check_perl($mode);

    # check mysql
    $pkg->check_mysql();

    # build lib/includes for following searches.
    my @libs = split(" ", $Config{libpth});
    my @lib_files;
    foreach my $lib (@libs) {
        next unless -d $lib;
        opendir(DIR, $lib) or die $!;
        push(@lib_files, grep { not -d $_ } readdir(DIR));
        closedir(DIR);
    }
    my @incs = ($Config{usrinc}, '/include', '/usr/local/include');

    # check for perl headers
    $pkg->check_libperl(lib_files => \@lib_files, includes => \@incs, mode => $mode);

    # check for libmysqlclient headers
    $pkg->check_libmysqlclient(lib_files => \@lib_files, includes => \@incs, mode => $mode);

    # check expat
    $pkg->check_expat(mode => $mode);

    # check various image libs
    $pkg->check_libjpeg(mode => $mode);
    $pkg->check_libgif(mode => $mode);
    $pkg->check_libpng(mode => $mode);
}

=item C<check_perl()>

Starting with V3, Krang can be used completely with UTF-8 so
we need to make sure that the Perl we are using has PerlIO
enabled.

We also verify that Perl is the right version and compiled for 
the right architecture (skipped in build mode).

=cut

sub check_perl {
    my ($pkg, $mode) = @_;

    # make sure we were built with PerlIO layers
    unless ($Config{useperlio}) {
        die <<END;

Krang needs a Perl that was built with PerlIO layer support.
This is the default and most systems stick with this default,
but yours does not. Please recompile Perl with PerlIO support.

END
    }

    return unless $mode eq 'install';

    # check that Perl is right for this build
    my %params = $pkg->build_params();

    my $perl = join('.', (map { ord($_) } split("", $^V, 3)));
    if ($perl ne $params{Perl}) {
        die <<END;

This distribution of Krang is compiled for Perl version
'$params{Perl}', but you have '$perl' installed.  You must either
install the expected version of Perl, or download a different release
of Krang.  Please see the installation instructions in INSTALL for
more details.

END
    }

    if ($Config{archname} ne $params{Arch}) {
        die <<END;

This distribution of Krang is compiled for the '$params{Arch}'
architecture, but your copy of Perl is compiled for
'$Config{archname}'.  You must download a different Krang
distribution, or rebuild your Perl installation.  Please see the
installation instructions in INSTALL for more details.

END
    }
}

=item C<check_mysql()>

The C<mysql> shell is available and MySQL is v4.0.13 or higher.

=cut

sub check_mysql {
    my ($pkg, %arg) = @_;
    my @PATH = split(':', ($ENV{PATH} || ""));

    # look for MySQL command shell
    die <<END unless grep { -e catfile($_, 'mysql') } @PATH;

MySQL not found.  Krang requires MySQL v4.0.13 or later.  If MySQL is 
installed, ensure that the 'mysql' client is in your PATH and try again.

END

    # check the version of MySQL
    no warnings qw(exec);
    my $mysql_version = `mysql -V 2>&1`;
    die "\n\nUnable to determine MySQL version using 'mysql -V'.\n" . "Error was '$!'.\n\n"
      unless defined $mysql_version and length $mysql_version;
    chomp $mysql_version;
    my ($major_version, $minor_version) = $mysql_version =~ /\s(4|5)\.(\d+\.\d+)/;

    die "\n\nMySQL version 4 not found.  'mysql -V' returned:" . "\n\n\t$mysql_version\n\n"
      unless defined $major_version;
    if ($major_version == 4) {
        die "\n\nMySQL version too old.  Krang requires v4.0.13 or higher.\n"
          . "'mysql -V' returned:\n\n\t$mysql_version\n\n"
          unless $minor_version >= 0.13;
    }
}

=item C<< check_libperl(lib_files => \@libs, includes => \@incs, mode => $mode) >>

Checks to see that the Perl libraries are installed.  The default
implementation looks in the standard locations plus $Config{archlib} 
for libperl.so or libperl.a

=cut

sub check_libperl {
    my ($pkg, %args) = @_;
    my @files = @{$args{lib_files}};

    # add $Config{archlib} since lots of distros place it in there
    my $extra_dir = catdir($Config{archlib}, 'CORE');
    if (-d $extra_dir) {
        opendir(DIR, $extra_dir) or die "Could not open $extra_dir for reading: $!";
        push(@files, grep { not -d $_ } readdir(DIR));
        closedir(DIR);
    }

    unless (grep { /^libperl\./ } @files) {
        die <<END;

Perl shared objects not found.  These are required for the proper operation of Krang.

Install the perl development libraries and try again.

END
    }
}

=item C<< check_libmysqlclient(lib_files => \@libs, includes => \@incs, mode => $mode) >>

Checks to see that the Perl libraries are installed.  The default
implementation looks in $Config{libpath} for libmysqlclient.so or libmysqlclient.a

=cut

sub check_libmysqlclient {
    my ($pkg, %args) = @_;
    my @files = @{$args{lib_files}};

    # add /usr/lib/mysql since lots of distros place it in there
    my $extra_dir = catdir('', 'usr', 'lib', 'mysql');
    if (-d $extra_dir) {
        opendir(DIR, $extra_dir) or die "Could not open $extra_dir for reading: $!";
        push(@files, grep { not -d $_ } readdir(DIR));
        closedir(DIR);
    }

    unless (grep { /^libmysqlclient\./ } @files) {
        die <<END;

MySQL client development libraries not found.  These are required for the proper operation of Krang.

Install the MySQL client development libraries and try again.

END
    }
}

=item C<< check_expat(lib_files => \@libs, includes => \@incs, mode => $mode) >>

Checks to see that the Expat library is installed. 

=cut

sub check_expat {
    my ($pkg, %args) = @_;
    $pkg->_check_libs(
        %args,
        module => 'XML::Parser',
        name   => 'libexpat',
        lib    => 'expat',
        h      => 'expat.h'
    );
}

=item C<< check_libjpeg(lib_files => \@libs, includes => \@incs, mode => $mode) >>

Checks for the existance of the libjpeg shared object and header files.
Header files are not needed for install.

=cut

sub check_libjpeg {
    my ($pkg, %args) = @_;

    $pkg->_check_libs(
        %args,
        module => 'Imager',
        name   => 'libjpeg',
        lib    => 'jpeg',

        # not sure why this fails to compile on Linux, but Imager has no problem with it...
        #h      => 'jpeglib.h',
    );
}

=item C<< check_libgif(lib_files => \@libs, includes => \@incs, mode => $mode) >>

Checks for the existance of the libgif or libungif shared object and header files.
Header files are not needed for install.

=cut

sub check_libgif {
    my ($pkg, %args) = @_;

    # check first for libgif.
    eval {
        $pkg->_check_libs(
            %args,
            module => 'Imager',
            name   => 'libgif',
            lib    => 'gif',
            h      => 'gif_lib.h'
        );
    };

    # if that fails, check for libungif (just as good).
    if ($@) {
        $pkg->_check_libs(
            %args,
            module => 'Imager',
            name   => 'libungif',
            lib    => 'ungif',
            h      => 'gif_lib.h'
        );
    }
}

=item C<< check_libpng(lib_files => \@libs, includes => \@incs, mode => $mode) >>

Checks for the existance of the libpng shared object and header files.
Header files are not needed for install.

=cut

sub check_libpng {
    my ($pkg, %args) = @_;

    $pkg->_check_libs(
        %args,
        module => 'Imager',
        name   => 'libpng',
        lib    => 'png',
        h      => 'png.h'
    );
}

=back

=item C<< $bin = find_bin(bin => $bin_name) >>

If $ENV{PATH} exists, searches $ENV{PATH} for $bin_name, returning the
full path to the desired executable.

If $ENV{PATH} does not contain /sbin or /usr/sbin, it will search those as well.

will die() with error if it cannot find the desired executable.

=cut

sub find_bin {

    my ($pkg, %args) = @_;

    my $bin = $args{bin};
    my $dir;

    my %additional_paths = (
        catdir('/', 'sbin') => 1,
        catdir('/', 'usr', 'sbin') => 1
    );

    my @PATH = split(':', ($ENV{PATH} || ""));

    foreach $dir (@PATH) {
        delete($additional_paths{$dir}) if ($additional_paths{$dir});
    }

    push @PATH, keys(%additional_paths);

    foreach $dir (@PATH) {

        my $exec = catfile($dir, $bin);

        return $exec if (-e $exec);
    }

    my $path = join ':', @PATH;

    die "Cannot find required utility '$bin' in PATH=$path\n\n";

}

=item C<< check_ip(ip => $ip) >>

Called by the installation system to check whether an IP address is
correct for the machine.  The default implementation runs
/sbin/ifconfig and tries to parse the resulting text for IP addresses.
Should return 1 if the IP address is ok, 0 otherwise.

=cut

sub check_ip {
    my ($pkg, %arg) = @_;
    my $IPAddress = $arg{ip};

    my $ifconfig = `/sbin/ifconfig`;
    my @ip_addrs = ();
    foreach my $if_line (split(/\n/, $ifconfig)) {
        next unless ($if_line =~ /inet\ addr\:(\d+\.\d+\.\d+\.\d+)/);
        my $ip = $1;
        push(@ip_addrs, $ip);
    }
    unless (grep { $_ eq $IPAddress } @ip_addrs) {
        return 0;
    }
    return 1;
}

=item C<< $gid = create_krang_group(options => \%options) >>

Called to create a Krang Group, as specified by the command-line
argument to bin/krang_install (--KrangGroup).  Takes the %options hash
built by krang_install as the one argument.

The default version of this sub works for GNU/Linux.  Other platforms
(e.g. BSD-like) will need to override this method to work with their
platforms' requirements for user creation.

The sub will check to see if --KrangGroup exists, and create it if it
does not.  It will return the group ID (gid) in either case.

This sub will die with an error if it cannot create --KrangGroup.

=cut

sub create_krang_group {
    my ($pkg, %args) = @_;

    my %options = %{$args{options}};

    my $groupadd_bin = $pkg->find_bin(bin => 'groupadd');

    my $KrangGroup = $options{KrangGroup};

    print "Creating UNIX group ('$KrangGroup')\n";
    my ($gname, $gpasswd, $gid, $gmembers) = getgrnam($KrangGroup);

    unless (defined($gid)) {
        my $groupadd = $groupadd_bin;
        $groupadd .= " $KrangGroup";
        system($groupadd) && die("Can't add group: $!");

        ($gname, $gpasswd, $gid, $gmembers) = getgrnam($KrangGroup);
        print "  Group created (gid $gid).\n";

    } else {
        print "  Group already exists (gid $gid).\n";
    }

    return $gid;
}

=item C<< $uid = create_krang_user(group_id => $gid, options => \%options) >>

Called to create a Krang User, as specified by the command-line
argument to bin/krang_install (--KrangUser).  Takes the %options hash
built by krang_install as the one argument.

The default version of this sub works for GNU/Linux.  Other platforms
(e.g. BSD-like) will need to override this method to work with their
platforms' requirements for user creation.

The sub will check to see if --KrangUser exists, and create it if it
does not.  If the user is created, the default group will be
--KrangGroup.  If the user already exists, it will be made a member of
the --KrangGroup group.

The sub will return the user ID (uid) if successful.

This sub will die with an error if it cannot create --KrangUser.

=cut

sub create_krang_user {

    my ($pkg, %args) = @_;

    my %options = %{$args{options}};

    my $useradd_bin = $pkg->find_bin(bin => 'useradd');

    my $KrangUser   = $options{KrangUser};
    my $KrangGroup  = $options{KrangGroup};
    my $InstallPath = $options{InstallPath};

    # Get KrangGroup info.
    my ($gname, $gpasswd, $gid, $gmembers) = getgrnam($KrangGroup);

    # Create user, if necessary
    print "Creating UNIX user ('$KrangUser')\n";
    my ($uname, $upasswd, $uid, $ugid, $uquota, $ucomment, $ugcos, $udir, $ushell, $uexpire) =
      getpwnam($KrangUser);

    unless (defined($uid)) {
        my $useradd = $useradd_bin;

        $useradd .= " -d $InstallPath -M $KrangUser -g $gid";
        system($useradd) && die("Can't add user: $!");

        # Update user data
        ($uname, $upasswd, $uid, $ugid, $uquota, $ucomment, $ugcos, $udir, $ushell, $uexpire) =
          getpwnam($KrangUser);
        print "  User created (uid $uid).\n";
    } else {
        print "  User already exists (uid $uid).\n";
    }

    # Sanity check - make sure the user is a member of the group.
    ($gname, $gpasswd, $gid, $gmembers) = getgrnam($KrangGroup);

    my @group_members = (split(/\s+/, $gmembers));
    my $user_is_group_member = (grep { $_ eq $KrangUser } @group_members);

    unless (($ugid eq $gid) or $user_is_group_member) {
        $pkg->krang_usermod(options => \%options);
    }

    return $uid;

}

=item C<< krang_usermod(options => \%options) >>

Called when --KrangUser is not a member of --KrangGroup.  This sub
adds --KrangUser to --KrangGroup.

The default version of this sub works for GNU/Linux.  Other platforms
(e.g. BSD-like) will need to override this method to work with their
platforms' requirements for user creation.

This sub will die with an error if it cannot make --KrangUser a member
of --KrangGroup.

=cut

sub krang_usermod {
    my ($pkg, %args) = @_;

    my %options = %{$args{options}};

    my $KrangUser  = $options{KrangUser};
    my $KrangGroup = $options{KrangGroup};

    print "  Adding user $KrangUser to group $KrangGroup.\n";

    my $usermod = $pkg->find_bin(bin => 'usermod');

    $usermod .= " -G $KrangGroup $KrangUser";

    system($usermod) && die("Can't add user $KrangUser to group $KrangGroup: $!");
    print "  User added to group.\n";

}

=item C<< build_perl_module(name => $name) >>

Called to build a specific Perl module distribution called C<$name> in
the current directory.  The result of calling this method should be
one or more compiled Perl modules in Krang's C<lib/> directory.

The default implementation includes code to answer questions asked by
some of the modules (using Expect) and special build procedures for
others.

The optional 'dest_dir' parameter specifies the location to put the
results of the build.  The default is KRANG_ROOT/lib.

=cut

sub build_perl_module {
    my ($pkg, %arg) = @_;
    my $name = $arg{name};
    my $dest_dir = $arg{dest_dir} || catdir($ENV{KRANG_ROOT}, 'lib');
    my $bin_dir = $arg{dest_dir}  || catdir($ENV{KRANG_ROOT}, 'lib', 'bin');

    # make sure our path contains the new bin dir
    local $ENV{PATH} = "$bin_dir:$ENV{PATH}";

    # load expect unless we're building it
    my $use_expect = ($name =~ /IO-Tty/ or $name =~ /Expect/) ? 0 : 1;
    _load_expect() if $use_expect;

    my $trash_dir = catdir(cwd, '..', 'trash');

    print "\n\n************************************************\n\n", " Building $name",
      "\n\n************************************************\n\n";

    # Net::FTPServer needs this to not try to install /etc/ftp.conf
    local $ENV{NOCONF} = 1 if $name =~ /Net-FTPServer/;

    # Module::Build or MakeMaker?
    my ($cmd, $make_cmd);
    if (-e 'Build.PL') {
        $cmd =
            "$^X Build.PL "
          . " --install_path lib=$dest_dir"
          . " --install_path libdoc=$trash_dir"
          . " --install_path script=$trash_dir"
          . " --install_path bin=$bin_dir"
          . " --install_path bindoc=$trash_dir"
          . " --install_path arch=$dest_dir/$Config{archname}";

        $make_cmd = './Build';
    } else {
        $cmd =
          "$^X Makefile.PL LIB=$dest_dir INSTALLBIN=$bin_dir INSTALLSCRIPT=$bin_dir PREFIX=$trash_dir INSTALLMAN3DIR=' ' INSTALLMAN1DIR=' '";
        $make_cmd = 'make';
    }

    # We only want the libs, not the executables or man pages
    if ($use_expect) {
        print "Running $cmd...\n";
        my $command = Expect->spawn($cmd);

        # setup command to answer questions modules ask
        my @responses = qw(n n n n n y ! /tmp 0007 y n n n y);
        while (
            my $match = $command->expect(
                undef,
                'ParserDetails.ini? [Y]',
                'remove gif support? [Y/n]',
                'mech-dump utility? [y]',
                'configuration (y|n) ? [no]',
                'unicode entities? [no]',
                'Do you want to skip these tests? [y]',
                "('!' to skip)",
                "UUID state storage",
                "default umask",
                "install Inline::C",
                "the 'runtests' utility",
                "optional module",
                "mandatory module",
                "Really skip",
            )
          )
        {
            $command->send($responses[$match - 1] . "\n");
        }
        $command->soft_close();
        if ($command->exitstatus() != 0) {
            die "$make_cmd failed: $?";
        }

        print "Running $make_cmd...\n";
        $command   = Expect->spawn($make_cmd);
        @responses = qw(n);
        while (my $match = $command->expect(undef, 'Mail::Sender? (y/N)',)) {
            $command->send($responses[$match - 1] . "\n");
        }
        $command->soft_close();
        if ($command->exitstatus() != 0) {
            die "$make_cmd failed: $?";
        }

    } else {

        # do it without Expect for IO-Tty and Expect installation.
        # Fortunately they don't ask any questions.
        print "Running $cmd...\n";
        system($cmd) == 0
          or die "$cmd failed: $?";
    }

    system("$make_cmd install") == 0 or die "$make_cmd install failed: $?";
}

=item C<< build_mm(mm_dir => $mm_dir, mm_bin => $mm_bin) >>

Called to build OSSP mm for shared memory allocation in Apache.

=cut

sub build_mm {
    my ($self,   %arg)    = @_;
    my ($mm_dir, $mm_bin) = @arg{qw(mm_dir mm_bin)};

    print "\n\n************************************************\n\n",
      "  Building OSSP mm - Shared Memory Allocation",
      "\n\n************************************************\n\n";

    my $mm_params = "--prefix=$mm_bin --exec-prefix=$mm_bin --disable-shared";

    my $olddir = cwd;
    chdir($mm_dir) or die "Unable to chdir($mm_dir): $!";

    system("./configure $mm_params") == 0 or die "MM configure failed: $!";
    system("make") == 0                   or die "MM make failed: $!";
    system("make install") == 0           or die "MM make install failed: $!";

    chdir($olddir);
}

=item C<< build_mm(build_dir => $dir, mod_ssl_dir => $dir, apache_dir => $dir) >>

Called to build mod_ssl to patch Apache.

=cut

sub build_mod_ssl {
    my ($self, %arg) = @_;
    my ($build_dir, $mod_ssl_dir, $apache_dir) = @arg{qw(build_dir mod_ssl_dir apache_dir)};

    print "\n\n************************************************\n\n", "  Building MOD_SSL",
      "\n\n************************************************\n\n";

    my $trash      = catfile($build_dir, 'mod_ssl_target');
    my $apache_src = catfile($build_dir, $apache_dir);
    mkdir($trash);
    my $mod_ssl_params = "--prefix=$trash " . "--with-apache=$apache_src";

    my $olddir = cwd;
    chdir($mod_ssl_dir) or die "Unable to chdir($mod_ssl_dir): $!";

    system("./configure $mod_ssl_params") == 0 or die "MOD_SSL configure failed: $!";

    chdir($olddir) or die "Unable to chdir($olddir): $!";
}

=item C<< build_apache_modperl(apache_dir => $dir, modperl_dir => $dir) >>

Called to build Apache and mod_perl in their respective locations.
Uses C<apache_build_parameters()> and C<modperl_build_parameters()>
which may be easier to override.  The result should be a working
Apache installation in C<apache/>.

=cut

sub build_apache_modperl {
    my ($pkg, %arg) = @_;
    my ($apache_dir, $mod_perl_dir, $mod_ssl_params) =
      @arg{qw(apache_dir mod_perl_dir mod_ssl_params)};
    _load_expect();

    print "\n\n************************************************\n\n", "  Building Apache/mod_perl",
      "\n\n************************************************\n\n";

    # gather params
    my $apache_params   = $pkg->apache_build_parameters(%arg);
    my $mod_perl_params = $pkg->mod_perl_build_parameters(%arg);

    # build mod_perl
    my $old_dir = cwd;
    chdir($mod_perl_dir) or die "Unable to chdir($mod_perl_dir): $!";
    print "Calling '$^X Makefile.PL $mod_perl_params'...\n";

    my $command = Expect->spawn("$^X Makefile.PL $mod_perl_params");

    # setup command to answer questions modules ask
    my @responses = qw(y n);
    while (my $match = $command->expect(undef, 'Configure mod_perl with', 'Shall I build httpd',)) {
        $command->send($responses[$match - 1] . "\n");
    }
    $command->soft_close();
    if ($command->exitstatus() != 0) {
        die "mod_perl Makefile.PL failed: " . $command->exitstatus();
    }

    system("make PERL=$^X") == 0
      or die "mod_perl make failed: $?";
    system("make install PERL=$^X") == 0
      or die "mod_perl make install failed: $?";

    # build Apache
    chdir($old_dir)    or die $!;
    chdir($apache_dir) or die "Unable to chdir($apache_dir): $!";
    print "Calling './configure $apache_params $mod_ssl_params'.\n";
    system("./configure $apache_params $mod_ssl_params") == 0
      or die "Apache configure failed: $?";
    system("make") == 0
      or die "Apache make failed: $?";
    if ($mod_ssl_params) {
        system("make certificate TYPE=DUMMY") == 0
          or die "Apache make certificate failed: $!";
    }
    system("make install") == 0
      or die "Apache make install failed: $?";

    # clean up unneeded apache directories
    my $KrangRoot = $ENV{KRANG_ROOT};
    system("rm -rf $KrangRoot/apache/man $KrangRoot/apache/htdocs/*");

}

=item C<< apache_build_parameters(apache_dir => $dir, modperl_dir => $dir) >>

Returns a string containing the parameters passed to Apache's
C<configure> script by C<build_apache_modperl()>.

=cut

sub apache_build_parameters {
    my $KrangRoot = $ENV{KRANG_ROOT};
    return "--prefix=${KrangRoot}/apache "
      . "--activate-module=src/modules/perl/libperl.a "
      . "--disable-shared=perl "
      . "--enable-module=rewrite      --enable-shared=rewrite "
      . "--enable-module=proxy        --enable-shared=proxy "
      . "--enable-module=mime_magic   --enable-shared=mime_magic ";
}

=item C<mod_perl_build_parameters(apache_dir => $dir, modperl_dir => $dir)>

Returns a string containing the parameters passed to mod_perl's
C<Makefile.PL> script by C<build_apache_modperl()>.

=cut

sub mod_perl_build_parameters {
    my ($pkg, %arg) = @_;
    my $KrangRoot = $ENV{KRANG_ROOT};
    my $trash = catdir(cwd, '..', 'trash');
    return "LIB=$KrangRoot/lib "
      . "PREFIX=$trash "
      . "APACHE_SRC=$arg{apache_dir}/src "
      . "USE_APACI=1 "
      . "EVERYTHING=1";
}

=item C<finish_installation(options => \%options)>

Anything that needs to be done at the end of installation can be done
here.  The default implementation does nothing.  The options hash
contains all the options passed to C<krang_install> (ex: InstallPath).

=cut

sub finish_installation { }

=item C<finish_upgrade()>

Anything that needs to be done at the end of an upgrade can be done
here.  The default implementation does nothing.

=cut

sub finish_upgrade { }

=item C<< post_install_message(options => \%options) >>

Called by bin/krang_install, returns install information once everything
is complete.

=cut

sub post_install_message {

    my ($pkg, %args) = @_;

    my %options = %{$args{options}};

    my @sslreport = $pkg->_get_ssl_report(\%options);

    my $report = <<EOREPORT;


#####                                                         #####
###                                                             ###
##                  KRANG INSTALLATION COMPLETE                  ##
###                                                             ###
#####                                                         #####


   Installed at        :  $options{InstallPath}
   Control script      :  $options{InstallPath}/bin/krang_ctl
   Krang conf file     :  $options{InstallPath}/conf/krang.conf

EOREPORT

    $report .= $sslreport[0];
    unless($options{NoStart}) {
        $report .= "\n\n  Running on $options{IPAddress} --\n" unless $options{NoStart};
        $report .= $sslreport[1];
        $report .= "    http://$options{HostName}:$options{ApachePort}/\n";
        $report .= "    ftp://$options{HostName}:$options{FTPPort}/\n";
    }

    $report .= $sslreport[2];

    if( $options{AdminPassword} ) {
        $report .= qq(   CMS admin user password:  "$options{AdminPassword}"\n);
    }

    print $report;
}

=item C<post_upgrade_message(options => \%options)>

Called by bin/krang_upgrade, returns upgrade information once everything
is complete.

=cut

sub post_upgrade_message {

    my ($pkg, %args) = @_;

    my %options = %{$args{options}};

    my @sslreport = $pkg->_get_ssl_report(\%options);

    print <<EOREPORT;


#####                                                         #####
###                                                             ###
##                  KRANG UPGRADE COMPLETE                       ##
###                                                             ###
#####                                                         #####


   Installed at        :  $options{InstallPath}
   Control script      :  $options{InstallPath}/bin/krang_ctl
   Krang conf file     :  $options{InstallPath}/conf/krang.conf
$sslreport[0]
   Running on $options{IPAddress} --
$sslreport[1]     http://$options{HostName}:$options{ApachePort}/
     ftp://$options{HostName}:$options{FTPPort}/

EOREPORT

}

=item C<guess_platform()>

Called to guess whether this module should handle building on this
platform.  This is used by C<krang_build> when the user doesn't
specify a platform.  This method should return true if the module
wants to handle the platform.

The default implementation returns false all the time.  When
implementing this module, err on the side of caution since the user
can always specify their platform explicitely.

=cut

sub guess_platform {
    return 0;
}

=item C<build_params()>

Reads the F<data/build.db> file produced by C<krang_build> and returns
a hash of the values available (Platform, Perl, Arch, SSL).

=cut

sub build_params {
    my $db_file = catfile($ENV{KRANG_ROOT}, 'data', 'build.db');
    return () unless -e $db_file;

    # it would be nice to use Config::ApacheFormat here, but
    # unfortunately it's not possible to guarantee that it will load
    # because it uses Scalar::Util which is an XS module.  If the
    # caller isn't running the right architecture then it will fail to
    # load.  So, fall back to parsing by hand...
    open(DB, $db_file) or die "Unable to open '$db_file': $!\n";
    my ($platform, $perl, $arch, $ssl);
    while (<DB>) {
        chomp;
        next if /^\s*#/;
        if (/^\s*platform\s+["']?([^'"]+)["']?/i) {
            $platform = $1;
        } elsif (/^\s*perl\s+["']?([^'"]+)/i) {
            $perl = $1;
        } elsif (/^\s*arch\s+["']?([^'"]+)/i) {
            $arch = $1;
        }
    }
    close DB;

    # check if SSL was built
    $ssl = -e catfile($ENV{KRANG_ROOT}, 'apache', 'libexec', 'libssl.so');

    return (
        Platform => $platform,
        Perl     => $perl,
        Arch     => $arch,
        SSL      => $ssl
    );
}

=back

=cut

# use Devel::CheckLib to look for external C libs and header files
sub _check_libs {
    my ($pkg, %args) = @_;

    my $mode   = $args{mode};
    my $name   = $args{name};
    my $lib    = $args{lib};
    my $h      = $args{h};
    my $module = $args{module};

    if ($lib) {
        my @libs;
        push(@libs, @{$args{libs}}) if $args{libs};    # extra dirs supplied when called
        eval { assert_lib(lib => $lib, libpath => \@libs, debug => $DEBUG) };
        die "\n\n$name is missing from your system, "
          . "Krang could not find it or we couldn't include it."
          . "\nThis library is required by Krang.\n\n"
          if $@;
    }

    if ($h && $mode eq 'build') {
        my @incs;
        push(@incs, @{$args{includes}}) if $args{includes};    # extra dirs supplied when called
        my $msg = "The header file for $name, '$h', is missing from your system "
          . ", Krang can't find it or we couldn't include it.";
        $msg .= "\nThis file is needed to compile the $module module which uses $name."
          if ($module && $name);
        eval { assert_lib(header => $h, incpath => \@incs, debug => $DEBUG) };
        die "$msg: $@\n" if $@;
    }
}

sub _load_expect {

    # load Expect - don't load at compile time because this module is
    # used during install when Expect isn't needed
    eval "require Expect";
    die <<END if $@;

Unable to load the Expect Perl module.  You must install Expect before
running krang_build.  The source packages you need are included with
Krang:

   src/IO-Tty-1.02.tar.gz
   src/Expect-1.15.tar.gz

END
}

sub _get_ssl_report {
    my ($pkg, $options) = @_;

    # Squash uninitialized values
    return ("", "", "") unless (($options->{SSLEngine} || "") eq "on");

    return (
        "   SSL files           :  $options->{InstallPath}/conf/\n",
        "     https://$options->{HostName}:$options->{ApacheSSLPort}/\n",
        "\n   Provided test SSL key and cert, make sure to generate valid ones\n\n"
    );
}

1;
