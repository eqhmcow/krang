package Fedora15::Platform;
use strict;
use warnings;

use base 'FedoraCore1::Platform';

sub guess_platform {
    return 0 unless -e '/etc/redhat-release';
    open(RELEASE, '/etc/redhat-release') or return 0;
    my $release = <RELEASE>;
    close RELEASE;
    return 1 if $release =~ /Fedora release 15/;
    return 0;
}

1;
