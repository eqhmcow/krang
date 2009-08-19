package Krang::URL;
use strict;
use warnings;

use Carp qw(croak);

=head1 NAME

Krang::URL - adjusting Krang object URLs to their publishing context

=head1 NOTICE: This module is DEPRECATED

Use $publisher-E<gt>url_for(object =E<gt> $object) instead, 
see L<Krang::Publisher>>.

For Backward-comptibility, pkg('URL')->real_url() is now just a wrapper
method that dispatches to it's successor: $publisher->url_for().

=head1 SYNOPSIS

  use Krang::ClassLoader 'URL';

  # get the real URL for a story
  my $story_url = pkg('URL')->real_url(object => $story, publisher => $publisher);

=head1 DESCRIPTION

Krang::URL provides one method to adjust the URL of certain objects to
the current publishing context (preview or publish).  When publishing
to preview, real_url() also checks the PreviewSSL config flag to
determine the URL's scheme (http or https).

Objects passed to real_url() are expected to have two methods:

=over

=item url(), returning the publish URL of the object

=item preview_url(), returning the preview URL of the object

=back

Per default, you may pass to real_url() objects of class
L<Krang::Story>, L<Krang::Media>, L<Krang::Category> and
L<Krang::Site>.

=head1 INTERFACE

=over

=item C<< real_url(object => $object, publisher => $publisher) >>

Returns the URL of $object according to the publishing context.

Returns the empty string if $object is not an object.

Croaks if $object does not have both methods url() and preview_url()

=cut

sub real_url {

    my ($self, %args) = @_;

    my ($object, $publisher) = @args{qw(object publisher)};

    return $publisher->url_for(object => $object);

}

1;
