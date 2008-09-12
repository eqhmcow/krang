package Krang::ElementClass::Media;

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader base => 'ElementClass::TopLevel';
use Krang::ClassLoader 'ElementLibrary';

=head1 NAME

Krang::ElementClass::Media - media element class

=head1 SYNOPSIS

   $class = pkg('ElementClass::Media')->new(name => "media");

=head1 DESCRIPTION

Provides a simple wrapper around TopLevel that media elements
can use to identify themselves.

=head1 INTERFACE

All the normal L<Krang::ElementClass::TopLevel> attributes and methods are available.

In addition, ElementClass::Media provides:

An element_class_name method that returns the name of the first toplevel 
element that inherits from ElementClass::Media.

A publish method that is called when a Media object is published.

An unpublish method that is called when a Media object is deleted.

=cut


=over

=item element_class_name()

Returns the name of the first toplevel element that inherits from ElementClass::Media

=cut

sub element_class_name {
    my ($name) = grep { pkg('ElementLibrary')->find_class(name => $_)->isa('Krang::ElementClass::Media') } (pkg('ElementLibrary')->top_levels);
    croak ('Could not find a toplevel element class that inherits from ElementClass::Media!!') unless $name;
    return $name;
}



=item publish()

Called when a media object is published

=cut

sub publish {
    my $pkg  = shift;
    my %args = @_;
    my $media     = $args{media};
    my $element   = $args{element};
    my $publisher = $args{publisher};

    # make sure any linked media objects are also published
    for my $linked_media ($media->linked_media) {
        my $linked_media_id = $linked_media->media_id; 
        my ($linked_media_object) = pkg('Media')->find(media_id => $linked_media_id); # pull from DB in case recursion already published it
        next unless $linked_media_object;

        if ($publisher->is_preview) {
            $linked_media_object->preview 
              unless $linked_media_object->preview_version;
        } else {
            $linked_media_object->publish
              unless $linked_media_object->published_version;
        }
    }
    
    # now we try to call each child element's publish() method. in stories, this "element walk" is done when the top-level
    # publish() calls fill_template(), which calls each child's publish() method, gathering their returned html into its
    # tmpl params, and they in turn take care of calling their kids' publish methods to build their html. since we're not building
    # up a structure of template params, we simply call each child's publish method for any desired side effects, ignoring return values.

    # we use an eval block around the publish() call because if one of the child elements is a container whose publish() method
    # has not been overridden, the SUPER's publish() method will look for an appropriate template, and, if it finds none, die
    # (which in our case shouldn't yield an error -- we're just calling these publish methods to do due diligence.)
    for my $child ($element->children) {
        eval { $child->publish(media     => $media,
                               publisher => $publisher,
                               element   => $child) };
    }
}



=item unpublish

Called when a media object is unpublished 

=cut

sub unpublish {
    my $pkg  = shift;
    my %args = @_;
    my $media     = $args{media};
    my $element   = $args{element};
    my $publisher = $args{publisher};

    for my $child ($element->children) {
        if ($child->class->can('unpublish')) {
            $child->class->unpublish(media     => $media,
                                    publisher => $publisher,
                                    element   => $child)
      }
    }
}

1;
