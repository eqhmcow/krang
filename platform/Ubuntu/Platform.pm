package Ubuntu::Platform;
use warnings;
use strict;

use base 'Krang::Platform';

# this 
sub guess_platform() {
    my $pkg = shift;

    # cannot be ubuntu if the lsb-release file does not exist.
    return 0 unless -e "/etc/lsb-release";

    open(RELEASE, '/etc/lsb-release') or return 0;
    my $release = <RELEASE>;
    close RELEASE;

    return 0 unless ($release =~ /DISTRIB_ID=Ubuntu/);

    # check for broken /bin/dash behavior
    $pkg->_check_bindash();

    return 1;
}


sub check_libperl {
    my ($pkg, %args) = @_;

    # use the parent expat check, just change the message.
    eval {
        $pkg->SUPER::check_libperl(%args);
    };

    return unless ($@);

    die <<END;

$@  \$ sudo apt-get install libperl-dev

END

}

sub check_libmysqlclient {
    my ($pkg, %args) = @_;

    # use the parent expat check, just change the message.
    eval {
        $pkg->SUPER::check_libmysqlclient(%args);
    };

    return unless ($@);

    die <<END;

$@  \$ sudo apt-get install libmysqlclient-dev

END

}


sub check_expat {
    my ($pkg, %args) = @_;

    # use the parent expat check, just change the message.
    eval {
        $pkg->SUPER::check_expat(%args);
    };

    return unless ($@);

    die <<END;

The Expat XML parser libraries were not found.  Install expat and try again.

  \$ sudo apt-get install libexpat1 libexpat1-dev

END

}


sub check_libjpeg {

    my ($pkg, %args) = @_;

    # use the parent expat check, just change the message.
    eval {
        $pkg->SUPER::check_libjpeg(%args);
    };

    return unless ($@);

    die <<END;

$@  \$ sudo apt-get install libjpeg-dev

END


}

sub check_libgif {

    my ($pkg, %args) = @_;

    # use the parent expat check, just change the message.
    eval {
        $pkg->SUPER::check_libgif(%args);
    };

    return unless ($@);

    die <<END;

$@  \$ sudo apt-get install libungif4g libungif4-dev

END

}

sub check_libpng {

    my ($pkg, %args) = @_;

    # use the parent expat check, just change the message.
    eval {
        $pkg->SUPER::check_libpng(%args);
    };

    return unless ($@);

    die <<END;

$@  \$ sudo apt-get install libpng12-dev

END

}


# ubuntu ships with /bin/sh pointing to /bin/dash, which breaks apache
# configure.
sub _check_bindash {
    my $pkg = shift;

    my $shell = readlink '/bin/sh';

    return 1 unless ($shell =~ /dash/);

    die <<END;

Ubuntu ships with /bin/sh pointing to /bin/dash.  Unfortunately, this
breaks the Apache build process (among other things).  Please run:

 \$ sudo dpkg-reconfigure dash

And reconfigure your system to not use /bin/dash for /bin/sh.

For more information, see README.Ubuntu.

END

}



1;

#sudo apt-get install libperl-dev libmysqlclient-dev
