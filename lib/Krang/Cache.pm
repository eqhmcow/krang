package Krang::Cache;
use strict;
use warnings;

use Krang::Log qw(info debug critical);

=head1 NAME

Krang::Cache - a read-only, non-persistent, private, LRU cache

=head1 SYNOPSIS

Turn on the cache:

  Krang::Cache::start();

Do some *read-only* work as usual:

  @stories = Krang::Story::find();
  $publisher->publish_stories(...);
  ...

Turn off the cache:

  Krang::Cache::stop();

=head1 DESCRIPTION

This module implements a read-only, non-persistent, private, LRU cache.
Let me break it down for you:

=over 4

=item readonly

This cache is read-only, which means that you can't use it if you'll
be trying to save objects in the cache.  Any attempt to do so will
result in an error.

=item non-persistent

This cache is held in memory and won't be visible in other processes.

=item private

Since the cache is in process memory it won't affect other processes.

=item LRU

This cache expires objects in Least Recently Used order.  Whenever an
object is requested from the cache it goes to the top of the list and
objects are always removed from the bottom when the cache is full.

=back

Currently the cache stores Krang::Element, Krang::User and
Krang::Group objects, and is used solely during publishing.

=head1 INTERFACE

=over 4

=item C<< Krang::Cache::start() >>

Start caching objects.  Calling this multiple times increments an
internal counter, so it's safe to have nested cache contexts and the
cache won't go off till the last one stop()s.

=item C<< Krang::Cache::stop() >>

Stop caching objects.  Calling this multiple times decrements an
internal counter and doesn't take effect till the count reaches 0.

B<NOTE>: It is very important to make sure stop() gets called after
start().  You should have an C<eval{}> around code between start() and
stop() and be sure to call stop() if the code die()s.  Failing to do
so can produce very strange results in persistent environments like
mod_perl.

=item C<< Krang::Cache::active() >>

Returns 1 if the cache is on, 0 if it's off.

=item C<< $size = Krang::Cache::size() >>

=item C<< Krang::Cache::size($size) >>

Get or set the cache size.  This is the number of objects allowed to
live in the cache at one time.  Setting this value less than the
current fill will cause objects to be removed.

The default cache size is 1000.

=item C<< ($hits, $loads, $fill) = Krang::Cache::stats() >>

Returns how many times the cache had the object requested, how many
objects have been loaded into the cache and how many objects currently
reside in the cache.  This may be called after C<stop()> and the
totals are zeroed by C<start()>.

=item C<< $obj = Krang::Cache::get('Krang::Element' => $element_id) >>

Request an object from the cache, using a class name and an id.
Returns C<undef> if the object is not in the cache or if the cache is
off.

=item C<< $obj = Krang::Cache::set('Krang::Element' => $element_id => $element) >>

Sets an object in the cache, using a class name, an id and a
reference to the object.

=back

=cut

# how many objects to store at any one time
our $CACHE_SIZE = 1000;

our %CACHE_POS;
our @CACHE;
our $CACHE_ON = 0;
our $CACHE_LOADS;
our $CACHE_HITS;
our $CACHE_FILL = 0;
our @CACHE_STACK;

use constant KEY   => 0;
use constant VALUE => 1;

sub start {
    $CACHE_ON++;
    if ($CACHE_ON == 1) {
        $CACHE_LOADS = 0;
        $CACHE_HITS  = 0;
        $CACHE_FILL  = 0;
    }
    push(@CACHE_STACK, [caller]);
}

sub stop {
    $CACHE_ON-- if $CACHE_ON;
    if ($CACHE_ON == 0) {
        %CACHE_POS = ();
        @CACHE     = ();
    }
    if (@CACHE_STACK) {
        my $frame = pop(@CACHE_STACK);
        debug("Krang::Cache::stop : ending cache started at " . join(', ', @$frame));
    } else {
        debug("Krang::Cache::stop : stopping already stopped cache.");
    }
}

sub active { $CACHE_ON ? 1 : 0 }

sub size {
    return $CACHE_SIZE unless @_;
    $CACHE_SIZE = shift;
    _cull() if $CACHE_FILL > $CACHE_SIZE;
}

sub get {
    return unless $CACHE_ON;

    # look up object
    my $key = $_[0] . $_[1];
    my $pos = $CACHE_POS{$key};
    return unless defined $pos;

    # got a hit, move it to the end
    $CACHE_HITS++;
    my $node = $CACHE[$pos];
    push(@CACHE, $node);
    $CACHE[$pos] = undef;
    $CACHE_POS{$key} = $#CACHE;

    # need to compress the cache?
    if (@CACHE > $CACHE_SIZE * 10) {
        my $spot = 0;
        foreach my $x (0 .. $#CACHE) {
            next unless defined $CACHE[$x];
            $CACHE[$spot] = $CACHE[$x];
            $CACHE_POS{$CACHE[$spot][KEY]} = $spot;
            $spot++;
        }
        $#CACHE = $spot - 1;
    }

    # all done
    return $CACHE[-1][VALUE];
}

sub set {
    return unless $CACHE_ON;
    my $key = $_[0] . $_[1];
    push(@CACHE, [$key, $_[2]]);
    $CACHE_POS{$key} = $#CACHE;
    $CACHE_LOADS++;
    $CACHE_FILL++;
    _cull() if $CACHE_FILL > $CACHE_SIZE;
}

# remove objects from the cache unless $CACHE_FILL == $CACHE_SIZE
sub _cull {
    my $node;
    foreach my $x (0 .. $#CACHE) {
        $node = $CACHE[$x];
        next unless defined $node and defined $node->[KEY];
        delete $CACHE_POS{$node->[KEY]};
        $CACHE[$x] = undef;
        $CACHE_FILL--;
        last if $CACHE_FILL == $CACHE_SIZE;
    }
}

sub stats { ($CACHE_HITS, $CACHE_LOADS, $CACHE_FILL); }

1;
