package Krang::Test::Util;
use strict;
use warnings;
use base 'Exporter';
our @EXPORT_OK = qw(restart_krang);

=head1 NAME

Krang::Test::Util - helpful testing routines 

=head1 SYNOPSIS

    use Krang::ClassLoader 'Test::Util' => qw(restart_krang);
    restart_krang() 
        or skip("Krang servers couldn't be restarted, skipping tests.", 7);
    
=head1 DESCRIPTION

This package provides some handy methods that simplify some common
repetitive tasks when testing Krang.

=cut

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader Conf => qw(
    KrangRoot 
    ApachePort 
    SiteServerPort 
    EnableSiteServer 
    FTPPort 
    EnableFTP 
    SSLApachePort 
    EnableSSL
);
use File::Spec::Functions qw(catfile);

=head1 INTERFACE

=head2 restart_krang

This routine will restart Krang and return true if successful

=cut

sub restart_krang {
    my $cmd = catfile(KrangRoot, 'bin', 'krang_ctl') . ' restart >/dev/null 2>&1';
    my @ports = (
        ApachePort,
        EnableSiteServer ? SiteServerPort : (),
        EnableFTP ? FTPPort : (),
        EnableSSL ? SSLApachePort : (),
    );
    # will need sudo?
    if ($< != 0 or $> != 0) {
        # are the ports reserved?
        if( grep { $_ <= 1024 } @ports ) {
            $cmd = "sudo $cmd";
        }
    }
    return system($cmd) == 0;
}

1;
