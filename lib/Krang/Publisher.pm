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

  # Remove a template from the production path.
  $publisher->undeploy_template(
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

use File::Spec::Functions;
use File::Copy qw(copy);
use File::Path;

use Krang::Conf qw(KrangRoot instance);
use Krang::Story;
use Krang::Category;
use Krang::ElementClass;
use Krang::Template;

use Krang::Log qw(debug info critical);

use constant PUBLISHER_RO => qw(is_publish is_preview story category);


use constant PAGE_BREAK   => "<<<<<<<<<<<<<<<<<< PAGE BREAK >>>>>>>>>>>>>>>>>>";
use constant CONTENT      => "<<<<<<<<<<<<<<<<<< CONTENT >>>>>>>>>>>>>>>>>>";

use Exception::Class
  'Krang::Publisher::FileWriteError' => {fields => [ 'story_id', 'media_id', 'template_id',
                                                     'source', 'destination', 'system_error' ] };


use Krang::MethodMaker (new_with_init => 'new',
                        new_hash_init => 'hash_init',
                        get           => [PUBLISHER_RO]
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


=item C<< $url = $publisher->preview_story(story => $story, category => $category) >>

Generates a story, saving it to the preview doc root on the filesystem.  Returns a URL to the story if successful, or will throw one of several potential Exceptions (potential issues: filesystem problems, exceptions thrown by other objects, anything else?) in the event something goes wrong.

category is an optional attribute.  By default, preview() will build a story based on the default category for the Story, otherwise it will preview the story in the supplied category.

As part of the publish process, all media and stories linked to by $story will be published to preview as well.

=cut

sub preview_story {

    my $self = shift;
    my %args = @_;
    my $category;
    my $url;

    my $preview_url;

    my $story = $args{story} || croak __PACKAGE__ . ": missing required argument 'story'";

    # in the event the category argument has been added, preview the story
    # using this category.
    # Otherwise, use the story's primary category.
    if (exists($args{category})) {
        $category = $args{category};
        croak "NOT IMPLEMENTED YET.\n";
    } else {
        $category = $story->category();
        $url = $story->preview_url();
    }

    # set internal mode - publish, not preview.
    $self->{is_publish} = 0;
    $self->{is_preview} = 1;

    info('Publisher.pm: Previewing story_id=' . $story->story_id());

    my $file_root = $category->site()->preview_path();

    # create output path.
    my $path = catfile($file_root, $url);

    # build the story HTML.
    my $story_pages = $self->_assemble_pages(story => $story, category => $category);

    # iterate over story pages, writing them to disk.
    for (my $p = 0; $p < @$story_pages; $p++) {
        my $page_num = $p + 1;

        # get the path & filename:
        my $filename = $self->_build_filename(story => $story, page => $page_num);

        # write the page to disk.
        $self->_write_page(path => $path, filename => $filename, 
                           story_id => $story->story_id(), data => $story_pages->[$p]);

    }

    $preview_url = "$url/" . $self->_build_filename(story => $story, page => 1);

    return $preview_url;
}

=item C<< $publisher->publish_story(story => $story, user => $user) >>

Publishes a story to the live webserver document root, as set by publish_path.

When a story is published, it is published under all categories it is associated with (see Krang::Story->categories()).

As part of the publish process, all media and stories linked to by $story will be published as well.

Will throw an exception if the user does not have permissions to publish.

=cut

sub publish_story {

    my $self = shift;
    my %args = @_;

    my $story = $args{story} || croak __PACKAGE__ . ": missing required argument 'story'";

    # get story URLs.
    my @story_urls = $story->urls();
    my @categories = $story->categories();

    # set internal mode - publish, not preview.
    $self->{is_publish} = 1;
    $self->{is_preview} = 0;

    info('Publisher.pm: Publishing story_id=' . $story->story_id());

    # Categories & Story URLs are in identical order.  Move in lockstep w/ both of them.
    foreach (my $i = 0; $i <= $#categories; $i++) {
        my $cat = $categories[$i];
        my $uri = $story_urls[$i];

        my $file_root = $cat->site()->publish_path();

        info("Publisher.pm: publishing story under URI='$uri'");

        # create output path.
        my $path = catfile($file_root, $uri);

        # build the story HTML.
        my $story_pages = $self->_assemble_pages(story => $story, category => $cat);

        # iterate over story pages, writing them to disk.
        for (my $p = 0; $p < @$story_pages; $p++) {
            my $page_num = $p + 1;

            # get the path & filename:
            my $filename = $self->_build_filename(story => $story, page => $page_num);

            # write the page to disk.
            $self->_write_page(path => $path, filename => $filename, 
                               story_id => $story->story_id(), data => $story_pages->[$p]);

        }
    }
}


=item C<< $url = $publisher->preview_media(media => $media) >>

Copies a media file out to the webserver doc root for the preview website.

Attributes media and category are required.

Returns a url to the media file on the preview website if successful.

Will throw an exception if there are problems with the copy.

=cut

sub preview_media {

    my $self = shift;
    my %args = @_;

    croak (__PACKAGE__ . ": Missing argument 'media'!\n") unless (exists($args{media}));

    my $media = $args{media};

    my $internal_path = $media->file_path();

    my $preview_path = catfile($media->category()->site()->preview_path(), $media->url());

    $preview_path =~ /^(.*\/)[^\/]+/;

    my $dir_path = $1;

    # make sure the output dir exists
    eval {mkpath($dir_path, 0, 0755); };
    if ($@) {
        Krang::Publisher::FileWriteError->throw(message => 'Could not create preview directory',
                                                destination => $dir_path,
                                                system_error => $@);
    }

    # copy file out to the production path
    unless (copy($internal_path, $preview_path)) {
        Krang::Publisher::FileWriteError->throw(message  => 'Could not preview media file',
                                                media_id => $media->media_id(),
                                                source   => $internal_path,
                                                destination => $preview_path,
                                                system_error => $!
                                               );
    }

    return $media->url();


}


=item C<< $url = $publisher->publish_media(media => $media, user => $user) >>

Copies a media file out to the webserver doc root for the publish website.

Attributes media and category are required.

Returns a url to the media file on the publish website if successful.

Will throw an exception if there are problems with the copy.

=cut

sub publish_media {
    my $self = shift;
    my %args = @_;

    croak (__PACKAGE__ . ": Missing argument 'media'!\n") unless (exists($args{media}));

    my $media = $args{media};

    my $internal_path = $media->file_path();

    my $publish_path = catfile($media->category()->site()->publish_path(), $media->url());

    $publish_path =~ /^(.*\/)[^\/]+/;

    my $dir_path = $1;

    # make sure the output dir exists
    eval {mkpath($dir_path, 0, 0755); };
    if ($@) {
        Krang::Publisher::FileWriteError->throw(message => 'Could not create publish directory',
                                                destination => $dir_path,
                                                system_error => $@);
    }

    # copy file out to the production path
    unless (copy($internal_path, $publish_path)) {
        Krang::Publisher::FileWriteError->throw(message  => 'Could not publish media file',
                                                media_id => $media->media_id(),
                                                source   => $internal_path,
                                                destination => $publish_path,
                                                system_error => $!
                                               );
    }

    return $media->url();

}


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

    croak (__PACKAGE__ . ": Missing argument 'template'!\n") unless (exists($args{template}));

    my $template   = $args{template};
    my $id         = $template->template_id();

    my $category   = $template->category();

    my @tmpl_dirs = $self->template_search_path(category => $category);

    my $path = $tmpl_dirs[0];

    eval {mkpath($path, 0, 0755); };
    if ($@) {
        Krang::Publisher::FileWriteError->throw(message => 'Could not create publish directory',
                                                destination => $path,
                                                system_error => $@);
    }


    my $file = catfile($path, $template->filename());

    # write out file
    my $fh = IO::File->new(">$file") or
      Krang::Publisher::FileWriteError->throw(message => 'Cannot deploy template',
                                              template_id => $id,
                                              destination => $file,
                                              system_error => $!);
    $fh->print($template->{content});
    $fh->close();

    info("Publisher.pm: template_id=$id deployed to '$file'");

    return $file;

}

=item C<< $publisher->undeploy_template(template => $template); >>

Removes the template specified by a L<Krang::Template> object from the template publish_path under $KRANG_ROOT.

The location of the template is based on $category->url() and $template->element_class_name().

If successful, undeploy_template() returns nothing.  In the event of an error, undeploy_template() will croak.

undeploy_template() makes no attempt to update the database as to the publish status or location of the template - that is the responsibility of Krang::Template (or should it call the appropriate method in Krang::Template?)

=cut

sub undeploy_template {

    my $self = shift;
    my %args = @_;

    croak (__PACKAGE__ . ": Missing argument 'template'!\n") unless (exists($args{template}));

    my $template   = $args{template};
    my $id         = $template->template_id();

    my $category   = $template->category();

    my @tmpls = $self->template_search_path(category => $category);
    my $path = $tmpls[0];

    my $file = catfile($path, $template->filename());

    if (-e $file) {
        if (-d $file) {
            croak __PACKAGE__ . ": template file '$file' is a directory - will not delete.\n";
        }
        unlink $file;
    }

    info("Publisher.pm: template_id=$id removed (undeployed) from location '$file'");

    return;

}


=item C<< $dir = $publisher->template_search_path(category => $category) >>

Given the current category, returns the list of directories that may contain a template.  The first element in the returning array contains the directory of the current category, the last element contains the directory of the root category (parent of all categories in the site).

L<category> is an optional argument - if not supplied, the current category in the publish run is used (usually the best choice).

=cut

sub template_search_path {

    my $self         = shift;
    my %args         = @_;
    my @subdirs      = ();
    my @paths        = ();
    my $category;

    # Root dir for this instance.
    my @root = (KrangRoot, 'data', 'templates', Krang::Conf->instance());

    if (exists($args{category})) {
        # if category arg is not defined, return root dir for instance.
        return catfile(@root) unless (defined($args{category}));
        $category = $args{category};
    } else {
        $category = $self->{category};
    }

    croak __PACKAGE__ . ': missing argument \'category\'' unless (defined($category));

    @subdirs = split '/', $category->url();

#    @subdirs = ('/') unless @subdirs;   # if $cat_dir == '/', @subdirs is empty.

    while (@subdirs > 0) {
        my $path = catfile(@root, @subdirs);
        push @paths, $path;
        pop @subdirs;
    }

    # add root dir as well.
    push @paths, catfile(@root);

    return @paths;

}


=item C<< $txt = page_break() >>

Returns the tag used internally to mark the break between pages in a story.  When a multi-page story is assembled by the Krang::ElementClass element tree, it consists of a scaler containing these break tags.  The preview/publish process will split the scaler along those tags to create the individual pages of the story.

No exceptions to throw.

=cut

sub page_break {

    return PAGE_BREAK;

}


=item C<< $txt = content() >>

Returns the tag used internally to mark the break between the top and bottom sections of a category page.  Once broken, the individual pages of a story will be placed in between the two halves, and the full HTML page will be assembled.

No exceptions to throw.

=back

=cut

sub content {

    return CONTENT;

}


=head1 TODO

Write out Krang::ElementClass POD and see if this still looks kosher.

Do alternate forms of output concern Krang::Publisher?  I assume any other form of output will be happen via the SOAP interface.

Write out all the methods for the POD listed here.

=head1 SEE ALSO

L<Krang::ElementClass>, L<Krang::Category>, L<Krang::Media>

=cut





#
# _assemble_pages()
#
# $pages_ref = $self->_assemble_pages(story    => $story,
#                                     category => $category
#                                    );
#
# _assemble_pages() is used internally by both publish() and preview()
# to mate the HTML generated by both the story and the category
# element trees.
#
# Attributes story and category are required.
#

sub _assemble_pages {

    my $self  = shift;
    my %args  = @_;
    my @pages = ();

    my $story    = $args{story};
    my $category = $args{category};

    # get root element for the story
    my $story_element    = $story->element();
    my $category_element = $category->element();

    # set internal values for accessor methods to call.
    $self->{category} = $category;
    $self->{story}    = $story;

    # get the HTML content for the story & category..
    my $article_output  = $story_element->class->publish(element   => $story_element,
                                                         publisher => $self);

    my $category_output = $category_element->class->publish(element   => $category_element,
                                                            publisher => $self);

    # break the story into pages
    my @article_pages = split(/${\PAGE_BREAK}/, $article_output);
    # break the category into header & footer.
    my ($cat_header, $cat_footer) = split(/${\CONTENT}/, $category_output, 2);

    # assemble the components.
    foreach (@article_pages) {
        my $page = $cat_header . $_ . $cat_footer;
        push @pages, $page
    }

    return \@pages;

}

#
# $filename = _build_filename(story => $story, page => $page_num)
#
# Returns the complete filename for the story being output.
# NOTE: As it stands now, page_num == 1 will be reduced to ''.
#

sub _build_filename {

    my $self = shift;
    my %args = @_;

    my $story = $args{story};
    my $page  = $args{page};

    my $element = $story->element();

    if ($page == 1) { $page = ''; }

    return $element->class()->filename() . $page . '.' . $element->class()->extension();

}


#
# _write_page(path => $path, filename => $filename, data => $content)
#
# Writes the content in $data to $path/$filename.
#
# Will croak if it cannot determine the filename, or
# cannot write to the filesystem.
#
# Returns nothing.
#
sub _write_page {

    my $self = shift;
    my %args = @_;

    foreach (qw(path filename)) {
        croak __PACKAGE__ . ": missing parameter '$_'.\n" unless defined ($args{$_});
    }

    eval { mkpath($args{path}, 0, 0755); };

    eval {mkpath($args{path}, 0, 0755); };
    if ($@) {
        Krang::Publisher::FileWriteError->throw(message => 'Could not create directory',
                                                destination => $args{path},
                                                system_error => $@);
    }


    my $output_filename = catfile($args{path}, $args{filename});

    my $fh = IO::File->new(">$output_filename") or
      Krang::Publisher::FileWriteError->throw(message      => 'Cannot output story',
                                              story_id     => $args{story_id},
                                              destination  => $output_filename,
                                              system_error => $!);
    $fh->print($args{data});
    $fh->close();

    info("Publisher.pm: wrote page '$output_filename'");

    return;
}


my $EBN =<<EOEBN;

This is a test of the emergency broadcast network.

Please stand by and await further instructions.

EOEBN
