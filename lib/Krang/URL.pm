package Krang::URL;
use strict;
use warnings;

use Krang::ClassLoader Conf => qw(PreviewSSL);

use Carp qw(croak);

=head1 NAME

Krang::URL - adjusting Krang object URLs to their publishing context

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

    my ($object, $publisher) = @args{ qw(object publisher) };

    return '' unless ref($object);

    $self->_check_object($object);

    if ($publisher->is_publish) {
	return 'http://' . $object->url;
    } elsif ($publisher->is_preview) {
	my $scheme = PreviewSSL ? 'https' : 'http';
	return "$scheme://" . $object->preview_url();
    } else {
	croak(__PACKAGE__ . ': Not in publish or preview mode. Cannot return proper URL.');
    }
}

sub _check_object {

    my($self, $object) = @_;

    for my $method ( qw(url preview_url) ) {
	unless ($object->can($method)) {
	    croak(__PACKAGE__. ': ' . ref($object) . " misses required method '$method'.");
	}
    }

    return 1;
}

1;
