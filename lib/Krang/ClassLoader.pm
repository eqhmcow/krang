package Krang::ClassLoader;
use strict;
use warnings;

use Krang::lib;
use Krang::ClassFactory qw(pkg);

=head1 NAME

Krang::ClassLoader - load Krang classes, using Krang::ClassFactory

=head1 SYNOPSIS

  # instead of this:
  use Krang::Element qw(foreach_element);

  # write this:
  use Krang::ClassLoader Element => qw(foreach_element);

  # for inheritence, instead of this:
  use base 'Krang::CGI';

  # write this
  use Krang::ClassLoader base => 'CGI';

=head1 DESCRIPTION

This module loads classes just like normal C<use>, but it looks up the
full class names using L<Krang::ClassFactory> before loading.

Ideally, this would work:

  use pkg('Element') qw(foreach_element);

Unfortunately Perl requires that class names passed to C<use> be
bare-words.

=head1 INTERFACE

None.

=cut

sub import {
    my ($self, $class, @args) = @_;

    my $pkg;
    if ($class eq 'base') {
        # decode super-class instead
        $pkg     = 'base';
        $args[0] = pkg($args[0]);
    } else {
        $pkg = pkg($class);
    }
    (my $file = "$pkg.pm") =~ s!::!/!g;
    require $file;

    if (my $m = $pkg->can('import')) {
        @_ = ($pkg, @args);
        goto &$m;
    }
}

1;
