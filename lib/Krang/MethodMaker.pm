package Krang::MethodMaker;
use strict;
use warnings;

use base qw(Class::MethodMaker);
use Carp qw(croak);

=head1 NAME

Krang::MethodMaker - extended version of Class::MethodMaker

=head1 SYNOPSIS

  # create a readonly foo_id() accessor and standard accessor/mutators
  # title() and url()
  use Krang::MethodMaker
    get     => ['foo_id'],
    get_set => ['title', 'url'];

=head1 DESCRIPTION

This class extends L<Class::MethodMaker> for use by Krang.  All the
normal Class::MethodMaker generators are available from
Krang::MethodMaker, with a few changes.

When we identify repeated code patterns we should consider adding a
method generator to this class.

=head1 INTERFACE

=over 4

=item get_set

Instead of defaulting to producing foo() and foo_clear(), Krang's
get_set takes none of the "flavor" options (-java, etc) and always
behaves as though -noclear were used.

Also, the code generated is faster than the default Class::MethodMaker
code since it doesn't use lexicals.

=cut

sub get_set {
    my ($class, @args) = @_;

    my %meths;
    foreach my $slot (@args) {
        $meths{$slot} = sub {
            return $_[0]->{$slot}
              if @_ == 1;
            return $_[0]->{$slot} = $_[1]
              if @_ == 2;
            croak "wrong # of args to '$slot' method: must be 0 or 1.\n";
        };
    }

    $class->install_methods(%meths);
}

=item get

Supplies just the get side of a get/set accessor.  This is useful for
readonly attributes, like object IDs.  These values will only be
mutable by setting the underlying hash key.

=cut

sub get {
    my ($class, @args) = @_;

    my %meths;
    foreach my $slot (@args) {
        $meths{$slot} = sub {
            return $_[0]->{$slot}
              if @_ == 1;
            croak "illegal attempt to set readonly attribute '$slot'.\n";
        };
    }

    $class->install_methods(%meths);
}

=back

=head1 TODO

=over

=item Write faster replacement for Class::MethodMaker::list() methods.

=back

=head1 SEE ALSO

L<Class::MethodMaker>

L<Krang::ElementClass>

=cut

1;
