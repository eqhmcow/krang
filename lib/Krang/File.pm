package Krang::File;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'AddOn';
use Krang::ClassLoader Conf => qw(KrangRoot);

use File::Spec::Functions qw(catfile);

=head1 NAME

Krang::File - find a file needed by Krang, searching addons and core

=head1 SYNOPSIS

  # find one file, searching through addons and the core
  $file = pkg('File')->find("/htdocs/images/arrow.png");

  # find all instances of a file
  @files = pkg('File')->find_all("/htdocs/images/arrow.png");

  # find all matches for a file glob
  @files = pkg('File')->find_glob("/htdocs/images/*.png");

  # forget past requests
  pkg('File')->flush_cache();

=head1 DESCRIPTION

This module finds files, searching through any installed addons and
then in core Krang.  This allows addons to override files in Krang
without overwriting them.

=head1 INTERFACE

=head2 C<< $file = Krang::File->find($path) >>

Returns the first instance of C<$path> in an addon or in Krang's core.

B<NOTE>: despite the name this method will find directories as well.
It's up to you to use -f or -d as needed.

=head2 C<< @files = Krang::File->find_all($path) >>

Returns all instances of C<$path> in an addon or in Krang's core.

=head2 C<< @files = pkg('File')->find_glob("/htdocs/images/*.png");

Returns all files matching a file glob in an addon or in Krang's core.

=head2 C<< Krang::File->flush_cache() >>

Drop the cache of files found.  This is needed if files are deleted or
new files are added which may override old requests.

=cut

our %CACHE;

sub find {
    return $CACHE{$_[1]} if exists $CACHE{$_[1]};

    my ($pkg, $file) = @_;
    my $root   = KrangRoot;
    my @addons = pkg('AddOn')->find();

    -e $_ and return $CACHE{$file} = $_ 
      for ((map { catfile($root, 'addons', $_->name, $file) } 
              pkg('AddOn')->find()), 
           catfile($root, $file));

    return $CACHE{$file} = undef;
}

sub flush_cache { %CACHE = (); }

sub find_all {
    my ($pkg, $file) = @_;
    my $root   = KrangRoot;
    my @addons = pkg('AddOn')->find();

    return grep { -e $_ }
      ((map { catfile($root, 'addons', $_->name, $file) } 
        pkg('AddOn')->find()), 
       catfile($root, $file));
}

sub find_glob {
    my ($pkg, $file) = @_;
    my $root   = KrangRoot;
    my @addons = pkg('AddOn')->find();

    my @files = glob(catfile($root, $file));
    foreach my $addon (pkg('AddOn')->find ) {
        unshift(@files, glob(catfile($root, 'addons', $addon->name, $file)));
    }

    return grep { -e $_ } @files;
}

1;
