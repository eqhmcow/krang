package Gentoo1_4_3::Platform;
use strict;
use warnings;

use base 'Krang::Platform';

sub guess_platform {
    return 0 unless -e '/etc/gentoo-release';
    open(RELEASE, '/etc/gentoo-release') or return 0;
    my $release = <RELEASE>;
    close RELEASE;
    return 1 if $release =~ /Gentoo Base System version 1.4.3/;
    return 0;
}


sub verify_dependencies {
    my ($pkg, %arg) = @_;


    # make sure we're running 5.8.2 or 5.8.3
    my $perl = join('.', (map { ord($_) } split("", $^V, 3)));

    unless ($perl eq '5.8.2' || $perl eq '5.8.3') {
        die sprintf("Your version of perl (%s) is not supported at the moment.\nPlease upgrade to 5.8.2 or 5.8.3.\n",
                    $perl);
    }

    return $pkg->SUPER::verify_dependencies(%arg);
}

1;
