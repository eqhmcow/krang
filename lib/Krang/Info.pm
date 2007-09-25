package Krang::Info;
use strict;
use warnings;
use Krang;

=head1 NAME

Krang::Info - info about the CMS

=head1 SYNOPSIS

  use Krang;
  use Krang::ClassFactory qw(pkg);
  use Krang::ClassLoader 'Info';
  print "This CMS is called ", pkg('Info')->product_name, "!\n";
  print "This is Krang version ", pkg('Info')->version, "!\n";

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

=back

=cut

1;
