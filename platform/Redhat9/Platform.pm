package Redhat9::Platform;
use strict;
use warnings;

use base 'Krang::Platform';

sub guess_platform {
    return 0 unless -e '/etc/redhat-release';
    open(RELEASE, '/etc/redhat-release') or return 0;
    my $release = <RELEASE>;
    close RELEASE;
    return 1 if $release =~ /Red Hat Linux release 9/;
    return 0;
}

1;
