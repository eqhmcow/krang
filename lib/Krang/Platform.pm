package Krang::Platform;
use strict;
use warnings;

use File::Spec::Functions qw(catdir catfile canonpath);
use Cwd qw(cwd);
use Config;

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

The default implementation checks for the following conditions:

=over

=item *

Perl is the right version and compiled for the right architecture
(skipped in build mode).

=item *

The C<mysql> shell is available and MySQL is v4.0.13 or higher.

=item *

The Expat library is installed.  The default implementation looks in
$Config{libpth} for libexpat.so.

=item *

libjpeg, libgif and libpng are installed with header files.  The
default implementation looks in $Config{libpth} for the appropriate
*.so files, and in $Config{usrinc} and /usr/local/include for the
header files (unless installing, in which case header files aren't
needed).

=back

=cut

sub verify_dependencies {
    my ($pkg, %arg) = @_;
    my $mode = $arg{mode};
    my @PATH = split(':', ($ENV{PATH} || ""));
    
    # look for MySQL command shell
    die <<END unless grep { -e catfile($_, 'mysql') } @PATH;

MySQL not found.  Krang requires MySQL v4.0.13 or later.  If MySQL is 
installed, ensure that the 'mysql' client is in your PATH and try again.

END
    
    # check the version of MySQL
    no warnings qw(exec);
    my $mysql_version = `mysql -V 2>&1`;
    die "\n\nUnable to determine MySQL version using 'mysql -V'.\n" .
      "Error was '$!'.\n\n"
        unless defined $mysql_version and length $mysql_version;
    chomp $mysql_version;
    my ($version) = $mysql_version =~ /\s4\.(\d+\.\d+)/;
    die "\n\nMySQL version 4 not found.  'mysql -V' returned:" .
      "\n\n\t$mysql_version\n\n"
        unless defined $version;
    die "\n\nMySQL version too old.  Krang requires v4.0.13 or higher.\n" .
      "'mysql -V' returned:\n\n\t$mysql_version\n\n"
        unless $version >= 0.13;

    # get ready to look for libs and include files
    my @libs = split(" ", $Config{libpth});
    my @incs = ($Config{usrinc}, '/include', '/usr/local/include');
    
    # look for Expat
    unless (grep { -e catfile($_, 'libexpat.so') } @libs) {
        die <<END;

Expat XML parser library not found.  Install expat
(http://expat.sf.net) and try again.

END
    }

    # look for libjpeg, libgif and libpng
    my @l = ( { name => 'libjpeg',
                so   => 'libjpeg.so',
                h    => 'jpeglib.h', },
              { name => 'libgif',
                so   => 'libgif.so',
                h    => 'gif_lib.h', },
              { name => 'libpng',
                so   => 'libpng.so',
                h    => 'png.h', } );
    foreach my $l (@l) {
        die "\n\n$l->{name} is missing from your system.\n".
          "This library is required by Krang.\n\n"
            unless grep { -e catfile($_, $l->{so}) } @libs;
        die <<END unless $mode eq 'install' or grep { -e catfile($_, $l->{h}) } @incs;

The header file for $l->{name}, '$l->{h}', is missing from your system.
This file is needed to compile the Imager module which uses $l->{name}.

END
    }



    if ($mode eq 'install') {
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
    unless (grep {$_ eq $IPAddress} @ip_addrs) {
        return 0;
    }
    return 1;
}

=item C<< build_perl_module(name => $name) >>

Called to build a specific Perl module distribution called C<$name> in
the current directory.  The result of calling this method should be
one or more compiled Perl modules in Krang's C<lib/> directory.

The default implementation includes code to answer questions asked by
some of the modules (using Expect) and special build procedures for
others.

=cut

sub build_perl_module {
    my ($pkg, %arg) = @_;
    my $name = $arg{name};
    _load_expect();

    my $dest_dir = catdir($ENV{KRANG_ROOT}, 'lib');
    my $trash_dir = catdir(cwd, '..', 'trash');
 
    print "\n\n************************************************\n\n",
          " Building $name",
          "\n\n************************************************\n\n";
         
    # Net::FTPServer needs this to not try to install /etc/ftp.conf
    local $ENV{NOCONF} = 1 if $name =~ /Net-FTPServer/;
    
    # We only want the libs, not the executables or man pages
    my $command =
      Expect->spawn("perl Makefile.PL LIB=$dest_dir PREFIX=$trash_dir MAN1PODS=\\{\\} MAN3PODS=\\{\\}");

    # setup command to answer questions modules ask
    my @responses = qw(n n n n n y !);
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
        )
      )
    {
        $command->send( $responses[ $match - 1 ] . "\n" );
    }
    $command->soft_close();
    if ( $command->exitstatus() != 0 ) {
        die "make failed: $?";
    }

    print "Running make...\n";
    $command = Expect->spawn('make');
    @responses = qw(n);
    while ( my $match = $command->expect( undef, 
                                          'Mail::Sender? (y/N)', 
                                        ) ) {
        $command->send($responses[ $match - 1 ] . "\n");
    }
    $command->soft_close();
    if ( $command->exitstatus() != 0 ) {
        die "make failed: $?";
    }

    system('make install') == 0 or die "make install failed: $?";   
}

=item C<< build_apache_modperl(apache_dir => $dir, modperl_dir => $dir) >>

Called to build Apache and mod_perl in their respective locations.
Uses C<apache_build_parameters()> and C<modperl_build_parameters()>
which may be easier to override.  The result should be a working
Apache installation in C<apache/>.

=cut

sub build_apache_modperl {
    my ($pkg, %arg) = @_;
    my ($apache_dir, $mod_perl_dir) = @arg{('apache_dir', 'mod_perl_dir')};
    _load_expect();

    print "\n\n************************************************\n\n",
          "  Building Apache/mod_perl",
          "\n\n************************************************\n\n";

    # gather params
    my $apache_params = $pkg->apache_build_parameters(%arg);
    my $mod_perl_params = $pkg->mod_perl_build_parameters(%arg);

    # build mod_perl
    my $old_dir = cwd;
    chdir($mod_perl_dir) or die "Unable to chdir($mod_perl_dir): $!";
    print "Calling 'perl Makefile.PL $mod_perl_params'...\n";

    my $command =
      Expect->spawn("perl Makefile.PL $mod_perl_params");

    # setup command to answer questions modules ask
    my @responses = qw(y n);
    while (my $match = $command->expect(
                                        undef,
                                        'Configure mod_perl with',
                                        'Shall I build httpd',
                                       )
          ) {
        $command->send( $responses[ $match - 1 ] . "\n" );
    }
    $command->soft_close();
    if ( $command->exitstatus() != 0 ) {
        die "mod_perl Makefile.PL failed: " . $command->exitstatus();
    }

    system("make") == 0
      or die "mod_perl make failed: $?";
    system("make install") == 0
      or die "mod_perl make install failed: $?";

    # build Apache
    chdir($old_dir) or die $!;
    chdir($apache_dir) or die "Unable to chdir($apache_dir): $!";
    print "Calling './configure $apache_params'.\n";
    system("./configure $apache_params") == 0
      or die "Apache configure failed: $?";
    system("make") == 0
      or die "Apache make failed: $?";
    system("make install") == 0
      or die "Apache make install failed: $?";
    
}

=item C<< apache_build_parameters(apache_dir => $dir, modperl_dir => $dir) >>

Returns a string containing the parameters passed to Apache's
C<configure> script by C<build_apache_modperl()>.

=cut

sub apache_build_parameters {
    my $KrangRoot = $ENV{KRANG_ROOT};
    return "--prefix=${KrangRoot}/apache ".
           "--activate-module=src/modules/perl/libperl.a ".
           "--disable-shared=perl ".
           "--enable-module=rewrite      --enable-shared=rewrite ".
           "--enable-module=proxy        --enable-shared=proxy ".
           "--enable-module=mime_magic   --enable-shared=mime_magic ";
}


=item C<mod_perl_build_parameters(apache_dir => $dir, modperl_dir => $dir)>

Returns a string containing the parameters passed to mod_perl's
C<Makefile.PL> script by C<build_apache_modperl()>.

=cut

sub mod_perl_build_parameters {
    my ($pkg, %arg) = @_;
    my $KrangRoot = $ENV{KRANG_ROOT};
    my $trash = catdir(cwd, '..', 'trash');
    return "LIB=$KrangRoot/lib " .
           "PREFIX=$trash " .
	   "APACHE_SRC=$arg{apache_dir}/src " .
   	   "USE_APACI=1 " .
	   "EVERYTHING=1";
}

=item C<finish_installation()>

Anything that needs to be done at the end of installation can be done
here.  The default implementation does nothing.

=cut

sub finish_installation {}

=item C<finish_upgrade()>

Anything that needs to be done at the end of an upgrade can be done
here.  The default implementation does nothing.

=cut

sub finish_upgrade {}

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
a hash of the values available (Platform, Perl, Arch).

=cut

sub build_params {
    my $db_file = catfile($ENV{KRANG_ROOT}, 'data', 'build.db');
    return () unless -e $db_file;

    # delay loading since Config::ApacheFormat won't be available
    # until after build
    eval "use Config::ApacheFormat";
    die $@ if $@;

    my $db = Config::ApacheFormat->new(
                   valid_directives => [qw( platform perl arch )],
                   valid_blocks     => []);
    eval { $db->read($db_file) };
    die "Unable to read data/build.db: $@\n" if $@;

    return ( Platform => $db->get('Platform'),
             Perl     => $db->get('Perl'),
             Arch     => $db->get('Arch') );
}

=back

=cut

sub _load_expect {
    # load Expect - don't load at compile time because this module is
    # used during install when Expect isn't needed
    eval "use Expect;";
    die <<END if $@;

Unable to load the Expect Perl module.  You must install Expect before
running krang_build.  The source packages you need are included with
Krang:

   src/IO-Tty-1.02.tar.gz
   src/Expect-1.15.tar.gz

END
}

1;
