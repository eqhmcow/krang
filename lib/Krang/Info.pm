package Krang::Info;
use strict;
use warnings;
use Krang;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'AddOn';
use Krang::ClassLoader Conf => 'Skin';
use Digest::MD5 qw(md5_hex);

=head1 NAME

Krang::Info - info about the CMS

=head1 SYNOPSIS

  use Krang;
  use Krang::ClassFactory qw(pkg);
  use Krang::ClassLoader 'Info';
  print "This CMS is called ", pkg('Info')->product_name, "\n";
  print "This is Krang version ", pkg('Info')->version, "\n";
  print "This string uniquely identifies an install", pkg('Info')->install_id, "\n";

=head1 DESCRIPTION

Contains the basic information about the running CMS that
is useful for addons to override (ie, to customize branding, etc).

=head1 INTERFACE

=over 

=item version

Returns the Krang version number.

=cut

sub version { $Krang::VERSION };

=item product_name

Returns the literal string 'Krang'.

=cut

sub product_name { 'Krang' };

=item install_id

Returns a string that identifies this install taking into account the
version, product_name, installed addons (and their versions) and the
current Skin.

One use for this is to provide a unique string for adding to the
URL of static assets to improve browser caching.

=cut

{
my $_ID;
sub install_id {
    if( !$_ID ) {
        my $pkg = shift;
        my $sep = '=:=';
        my @addons = pkg('AddOn')->find();
        my $ident = join(
            $sep,
            $Krang::VERSION,
            $pkg->version,
            $pkg->product_name,
            ( map { $_->name, $_->version } @addons ),
            Skin(),
        );
        $_ID = md5_hex($ident);
    }
    return $_ID;
}
}

=back

=cut

1;
