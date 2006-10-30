package Krang::UUID;
use strict;
use warnings;

use Data::UUID;
our $UUID = Data::UUID->new();

sub new { $UUID->create_str() }

1;

__END__

=head1 NAME

Krang::UUID - provide unqiue identfiers

=head1 SYNOPSIS

  use Krang::ClassLoader 'UUID';

  # create a new UUID string
  $uuid = pkg('UUID')->new();

=head1 DESCRIPTION

This is a wrapper around Data::UUID which provides a consistent
interface for all Krang classes.  UUIDs returned are always in string
format (ex. 98DBE9EE-684A-11DB-8805-80D0EC6873C7) and thus may be
reliably compared with C<eq>.

=head1 INTERFACE

=head2 new

Returns a new UUID string.

=cut

