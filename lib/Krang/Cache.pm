package Krang::Cache;
use strict;
use warnings;

# default cache parameters
use constant CACHE_SIZE   => 10 * 1024 * 1024; # 10M
use constant PAGE_SIZE    => 4 * 1024;         # 4k
use constant BUCKET_SIZE  => 4 * 1024;         # 4k
use constant BUCKET_COUNT => (CACHE_SIZE / BUCKET_SIZE);

# turn the cache off, useful for benchmarking and testing
use constant CACHE_OFF => 0;

use Krang::Conf qw(KrangRoot);
use File::Path qw(mkpath);
use File::Spec::Functions qw(catfile catdir);
use Cache::Mmap;

=head1 NAME

Krang::Cache - cache control module

=head1 SYNOPSIS

  use Krang::Cache;

  # get a handle for a particular cache
  $cache = Krang::Cache->new(name => 'category');

  # read an object from the cache, using the ID as the key
  $obj = $cache->read($category_id);

  # write an object to the cache
  $cache->write($category_id => $category);

  # delete an object from the cache
  $cache->delete($category_id);

  # clear the whole cache
  $cache->clear();

=head1 DESCRIPTION

This module provides a layer around Cache::Mmap for use by Krang
modules.  There are a few important things to keep in mind when using
this module:

=over

=item *

Never write anything to the cache that hasn't already been commited to
the database.

=item *

Never make a change to a cached object in the database without either
writing to the cache or deleting any entry for the object.

=item *

It is possible that your object will not be stored in the cache after
a write().  It might be too big, or it might get evicted by other
objects before you get a chance to call read().  For that reason you
cannot rely on the cache to store your data.  It's there for a
potential speedup, but that's it!

=back

=head1 INTERFACE

=over

=item C<< $cache = Krang::Cache->new(name => 'category') >>

Returns a cache object which can be used to read and write cache
entries.  Each cache must have a unique name.  If the cache does not
yet exist it will be created.

=cut

sub new {
    my ($pkg, %arg) = @_;
    my $self = bless({}, $pkg);

    my $name = $arg{name} || croak("Missing required name parameter");
    $self->{name} = $name;

    # determine cace path and filename
    my $instance = Krang::Conf->instance();
    my $cache_dir = catdir(KrangRoot, "data", "cache", $instance);
    my $cache_file = catfile($cache_dir, $name);

    # make directory if needed
    mkpath($cache_dir) unless -d $cache_dir;
    
    # get mmap handle, will create file if it does not exist
    my $mmap = Cache::Mmap->new($cache_file,                 
                                { bucketsize => BUCKET_SIZE,
                                  buckets    => BUCKET_COUNT,
                                  pagesize   => PAGE_SIZE });
    croak("Unable to create mmap cache '$cache_file'")
      unless $mmap;
    $self->{mmap} = $mmap;
    
    return $self;
}

=item C<< $obj = $cache->read($id) >>

Fetches an object from the cache, keyed by ID.  Will return undef if
the object does not exist in the cache.  Remember that this may return
C<undef> even if you just called write()!

=cut

sub read { $_[0]->{mmap}->read($_[1]); }

=item C<< $cache->write($id, $obj) >>

Writes an object to the cache, keyed by ID.

=cut

sub write { $_[0]->{mmap}->write($_[1], $_[2]); }

=item C<< $cache->delete($id) >>

Deletes an object from the cache, keyed by ID.

=cut

sub delete { $_[0]->{mmap}->delete($_[1]); }

=item C<< $cache->clear() >>

Clears all objects from the cache.

=cut

sub clear {
    my $self = shift;
    my $mmap = $self->{mmap};
    foreach my $key ($mmap->entries()) {
        $mmap->delete($key);
    }
}

=back

=cut

1;
