package Krang::Publisher;


=head1 NAME

Krang::Publisher - Center of the Publishing Universe.

=head1 SYNOPSIS

  use Krang::Publisher;

  my $publisher = new Krang::Publisher();


  # Outputs a story in the previously-set preview path,
  # returns preview URL.
  my $url = $publisher->preview_story(
                                      story    => $story_object,
                                      category => $category_object
                                     );


  # Outputs a story in the previously-set publish path.
  $publisher->publish_story(
                            story    => $story_object,
                            user     => $user_object
                           );


  # Publish a media object to the preview path.
  # Returns the media URL if successful.
  $url = $publisher->preview_media(
                                   media    => $media_object
                                  );

  # Publish a media object to the preview path.
  # Returns the media URL if successful.
  $url = $publisher->publish_media(
                                   media    => $media_object,
                                   user     => $user_object
                                  );


  # Get the list of related stories and media that will get published
  my ($story_list, $media_list) = $publisher->get_publish_list(story => $story);

  # Place a template into the production path, to be used when publishing.
  $publisher->deploy_template(
                              template => $template_object
                             );


  # Returns the mark used internally to break content into pages.
  my $break_txt = $publisher->PAGE_BREAK();

  # Return the Krang::Story object of the story currently being published.
  my $story = $publisher->story();

  # Return the category object for the current category of the story being published.
  my $category = $publisher->category();



=head1 DESCRIPTION

Krang::Publisher is responsible for coordinating the various components that make up a Story (Elements, Media, Categories), and putting them all together, out on the filesystem, for the world + dog to see.  The publish process will result in either 'preview' or 'publish' output - content-wise, they are indistinguishable.

In both the preview and publish process, stories are checked for related media (see Krang::Story::linked_media()).  Media objects will be copied into the proper output directory as part of the build process.

In the publish (but not preview) process, stories will also be checked for linked stories (see Krang::Story::linked_stories()).  Any linked-to stories will be checked for publish status, and will be published if they are marked as unpublished.

=cut

use strict;
use warnings;

use Carp;

use File::Spec;
use File::Path;

use Krang::Conf qw(KrangRoot instance);
use Krang::Story;
use Krang::Category;
use Krang::ElementClass;
use Krang::Template;

use constant PUBLISHER_RO => qw(is_publish is_preview story category);

use Krang::MethodMaker (new_with_init => 'new',
                        new_hash_init => 'hash_init',
                        get_set       => [PUBLISHER_RO]
                       );



=head1 INTERFACE

=head2 FIELDS

Access to fields for this object are provided by Krang::MethodMaker. All fields are accessible in a B<read-only> fashion.  The value of fields can be obtained in the following fashion:

  $value = $publisher->field_name();

The available fields for a publish object are:

=over

=item * is_preview

Returns a 1 if the current publish run is in preview-mode, 0 otherwise.

=item * is_publish

Returns a 1 if the current publish run is in publish-mode (e.g. going live), 0 otherwise.

=item * category

Returns a Krang::Category object for the category currently being published.

=item * story

Returns a Krang::Story object for the Story currently being published.

=back

=cut

=head2 METHODS

=over

=item C<< $publisher = Krang::Publisher->new(); >>

Creates a new Krang::Publisher object.  No parameters are needed at this time.

=item C<< $url = $publisher->preview_story(story => $story, category => $category) >>

Generates a story, saving it to the preview doc root on the filesystem.  Returns a URL to the story if successful, or will throw one of several potential Exceptions (potential issues: filesystem problems, exceptions thrown by other objects, anything else?) in the event something goes wrong.

category is an optional attribute.  By default, preview() will build a story based on the default category for the Story, otherwise it will preview the story in the supplied category.

As part of the publish process, all media and stories linked to by $story will be published to preview as well.

=item C<< $publisher->publish_story(story => $story, user => $user) >>

Publishes a story to the live webserver document root, as set by publish_path.

When a story is published, it is published under all categories it is associated with (see Krang::Story->categories()).

As part of the publish process, all media and stories linked to by $story will be published as well.

Will throw an exception if the user does not have permissions to publish.

=cut

=item C<< $url = $publisher->preview_media(media => $media) >>

Copies a media file out to the webserver doc root for the preview website.

Attributes media and category are required.

Returns a url to the media file on the preview website if successful.

Will throw an exception if there are problems with the copy.

=cut

=item C<< $url = $publisher->publish_media(media => $media, user => $user) >>

Copies a media file out to the webserver doc root for the publish website.

Attributes media and category are required.

Returns a url to the media file on the publish website if successful.

Will throw an exception if there are problems with the copy.

=cut

=item C<< ($stories, $media) = $publisher->get_publish_list(story => $story) >>

Returns the list of stories and media objects that will get published if publish_story(story => $story) is called.

The sub calls $story->linked_stories() and $story->linked_media() to generate the lists, recursively operating on the results generated by $story->linked_stories().

If successful, it will return lists of Krang::Story and Krang::Media objects that will get published along with $story.  At the absolute minimum (no linked stories or media), $stories->[0] will contain the originally submitted parameter $story.

=cut

=item C<< $filename = $publisher->deploy_template(template => $template); >>

Deploys the template stored in a L<Krang::Template> object into the template publish_path under $KRANG_ROOT.

The final path of the template is based on $category->url() and $template->element_class_name().

If successful, deploy_template() returns the final resting place of the template.  In the event of an error, deploy_template() will croak.

deploy_template() makes no attempt to update the database as to the publish status or location of the template - that is the responsibility of Krang::Template (or should it call the appropriate method in Krang::Template?)

=cut

sub deploy_template {

    my $self = shift;
    my %args = @_;

    croak ("Missing argument 'template'!\n") unless (exists($args{template}));

    my $template   = $args{template};
    my $id         = $template->template_id();
    my ($category) = Krang::Category->find(category_id => $template->category_id());

    if (!defined($category)) { die "ERROR: cannot find category '" . $template->category_id() . "'\n"; }

    my @tmpl_dirs = $self->template_search_path(category => $category);

    my $path = $tmpl_dirs[0];
    mkpath($path, 0, 0755);

    my $file = File::Spec->catfile($path, $template->filename());

    # write out file
    my $fh = IO::File->new(">$file") or
      croak(__PACKAGE__ . "->deploy_template(): Unable to write to '$file' for " .
            "template '$id': $!.");
    $fh->print($template->{content});
    $fh->close();

    return $file;

}


=item C<< $dir = $publisher->template_search_path(category => $category) >>

Given the current category, returns the list of directories that may contain a template.  The first element in the returning array contains the directory of the current category, the last element contains the directory of the root category (parent of all categories in the site).

L<category> is an optional argument - if not supplied, the current category in the publish run is used (usually the best choice).

=cut

sub template_search_path {

    my $self = shift;
    my %args = @_;
    my $category = $args{category} || $self->{category};

    my @paths = ();

    # Root dir for this instance.
    my @root = (KrangRoot, 'data', 'templates', Krang::Conf->instance());

    my $cat_dir = $category->url();

    my @subdirs = split '/', $cat_dir || ('/');

    @subdirs = ('/') unless @subdirs;   # if $cat_dir == '/', @subdirs is empty.

    while (@subdirs > 0) {
        my $path = File::Spec->catfile(@root, @subdirs);
        push @paths, $path;
        pop @subdirs;
    }

    return @paths;

}


=item C<< PAGE_BREAK() >>

Returns the tag used internally to mark the break between pages in a story.  When a multi-page story is assembled by the Krang::ElementClass element tree, it consists of a scaler containing these break tags.  The preview/publish process will split the scaler along those tags to create the individual pages of the story.

No exceptions to throw.

=back

=cut

=head1 TODO

Write out Krang::ElementClass POD and see if this still looks kosher.

Do alternate forms of output concern Krang::Publisher?  I assume any other form of output will be happen via the SOAP interface.

Write out all the methods for the POD listed here.

=head1 SEE ALSO

L<Krang::ElementClass>, L<Krang::Category>, L<Krang::Media>

=cut


#
# init()
#
# Sanity check as part of load.
#
sub init {

    my $self = shift;
    my %args = @_;

    $self->hash_init(%args);

    return;
}



#
# _assemble_pages()
#
# @pages = $self->_assemble_pages(story => $story, category => $category);
#
# _assemble_pages() is used internally by both publish() and preview()
# to mate the HTML generated by both the story and the category
# element trees.
#
# Attributes story and category are required.
#

my $EBN =<<EOEBN;

This is a test of the emergency broadcast network.

Please stand by and await further instructions.

EOEBN
