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
                                  );


  # Get the list of related stories and media that will get published
  my $asset_list_ref = $publisher->get_publish_list(story => [$story1, $story2]);

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
use File::Temp qw(tempdir);

use Krang::Conf qw(KrangRoot instance);
use Krang::Story;
use Krang::Category;
use Krang::ElementClass;
use Krang::Template;
use Krang::History qw(add_history);

use Krang::Log qw(debug);


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

    # build the story HTML.
    local $ENV{HTML_TEMPLATE_ROOT} = "";

    # deploy any templates flagged as testing for this user
    $self->_deploy_testing_templates();

    my $publish_list = $self->get_publish_list(story => [$story]);

    foreach my $object (@$publish_list) {
        if ($object->isa('Krang::Story')) {
            debug('Publisher.pm: Previewing story_id=' . $object->story_id());
            $self->_build_story_single_category(story    => $object,
                                                category => $object->category,
                                                url      => $object->preview_url());
        } elsif ($object->isa('Krang::Media')) {
            debug('Publisher.pm: Previewing media_id=' . $object->media_id());
            $self->preview_media(media => $object);
        }
    }


    # cleanup - remove any testing templates.
    $self->_undeploy_testing_templates();

    $preview_url = "$url/" . $self->_build_filename(story => $story, page => 1);

    return $preview_url;
}

=item C<< $publisher->publish_story(story => $story) >>

Publishes a story to the live webserver document root, as set by publish_path.

When a story is published, it is published under all categories it is associated with (see Krang::Story->categories()).

As part of the publish process, all media and stories linked to by $story will be published as well.

Will throw an exception if the current user ($ENV{REMOTE_USER})does not have permissions to publish.

=cut

sub publish_story {

    my $self = shift;
    my %args = @_;

    my $story = $args{story} || croak __PACKAGE__ . ": missing required argument 'story'";

    # set internal mode - publish, not preview.
    $self->{is_publish} = 1;
    $self->{is_preview} = 0;

    my $publish_list = $self->get_publish_list(story => $story);

    foreach my $object (@$publish_list) {
        if ($object->isa('Krang::Story')) {
            $self->_build_story_all_categories(story => $object);
            # check the object back in.
            if ($object->checked_out()) { $object->checkin(); }
        } elsif ($object->isa('Krang::Media')) {
            $self->publish_media(media => $object);
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

    my $preview_path = catfile($media->category()->site()->preview_path(), $media->preview_url());

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

    return $media->preview_url();


}


=item C<< $url = $publisher->publish_media(media => $media) >>

Copies a media file out to the webserver doc root for the publish website.

Attributes media and category are required.

Returns a url to the media file on the publish website if successful.

Will throw an exception if there are problems with the copy.

=cut

sub publish_media {
    my $self = shift;
    my %args = @_;
    my @urls;

    croak (__PACKAGE__ . ": Missing argument 'media'!\n") unless (exists($args{media}));

    if (ref $args{media} eq 'ARRAY') {
        foreach (@{$args{media}}) {
            push @urls, $self->_write_media($_);
        }
        return @urls;
    }
    return $self->_write_media($args{media});
}



=item C<< $publish_list_ref = $publisher->get_publish_list(story => $story) >>

Returns the list of stories and media objects that will get published if publish_story(story => $story) is called.

The sub calls $story->linked_stories() and $story->linked_media() to generate the lists, recursively operating on the results generated by $story->linked_stories().

If successful, it will return lists of Krang::Story and Krang::Media objects that will get published along with $story.  At the absolute minimum (no linked stories or media), $stories->[0] will contain the originally submitted parameter $story.

The story parameter can either be a single Krang::Story object or a list or Krang::Story objects.

=cut

sub get_publish_list {

    my $self = shift;
    my %args = @_;

    croak (__PACKAGE__ . ": Missing argument 'story'!") unless (exists($args{story}));

    my @publish_list;

    if (ref $args{story} eq 'ARRAY') {
        my $stories = $args{story};
        foreach my $story (@$stories) {
            push @publish_list, $self->_add_to_publish_list($story);
        }
    } else {
        push @publish_list, $self->_add_to_publish_list($args{story});
    }
    delete $self->{stories_to_be_published};
    delete $self->{media_to_be_published};
    delete $self->{stories_checked_for_links};

    return \@publish_list;

}


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

    my $template = $args{template};

    # write the template out.
    my $filename = $self->_write_template(template => $template);

    # mark template as deployed.
    $template->mark_as_deployed();

    # log event.
    add_history(object => $template, action => 'deploy');

    return $filename;

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

    my $category   = $template->category();

    my @tmpl_paths = $self->template_search_path(category => $category);
    my $path = $tmpl_paths[0];

    my $file = catfile($path, $template->filename());

    if (-e $file) {
        if (-d $file) {
            croak __PACKAGE__ . ": template file '$file' is a directory - will not delete.\n";
        }
        unlink $file;
    }

    # mark template as undeployed.
    $template->mark_as_undeployed();

    # log event.
    add_history(object => $template, action => 'undeploy');

    return;

}


=item C<< $dir = $publisher->template_search_path(category => $category) >>

Given the current category, returns the list of directories that may contain a template.  The first element in the returning array contains the directory of the current category, the last element contains the directory of the root category (parent of all categories in the site).

L<category> is an optional argument - if not supplied, the current category in the publish run is used (usually the best choice).

A note on preview:  In preview mode, this method will check to see if the user has a testing-template temporary directory (created if the user has templates checked out & flagged for testing).  If so, the testing-template temporary directory paths will be interspersed with the deployed-template dirs (in the order of TEST/PROD/TEST/PROD).

=cut

sub template_search_path {

    my $self         = shift;
    my %args         = @_;
    my @subdirs      = ();
    my @paths        = ();
    my $category;
    my $preview_root;

    my $user_id = $ENV{REMOTE_USER};


    # Root dir for this instance.
    my @root = (KrangRoot, 'data', 'templates', Krang::Conf->instance());

    if (exists($args{category})) {
        if (!defined($args{category})) {
            # if category arg is not defined, return root dir for instance.
            # (but check for template testing)
            if ($self->{is_preview} &&
                exists($self->{testing_template_path}{$user_id})) {
                return ($self->{testing_template_path}{$user_id}, catfile(@root));
            }
            return catfile(@root);
        }

        $category = $args{category};
    } else {
        $category = $self->{category};
    }

    croak __PACKAGE__ . ': missing argument \'category\'' unless (defined($category));

    @subdirs = split '/', $category->url();

    while (@subdirs > 0) {
        # if in preview mode, check to see if there's a template testing dir.
        # add it if there is.
        if ($self->{is_preview} &&
            exists($self->{testing_template_path}{$user_id})) {
            push @paths, catfile($self->{testing_template_path}{$user_id}, @subdirs);
        }

        push @paths, catfile(@root, @subdirs);
        pop @subdirs;
    }

    # add root (possibly preview too) dir as well.
    if ($self->{is_preview} &&
        exists($self->{testing_template_path}{$user_id})) {
        push @paths, $self->{testing_template_path}{$user_id};
    }

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

Pagination

=head1 SEE ALSO

L<Krang::ElementClass>, L<Krang::Category>, L<Krang::Media>

=cut


#
# _deploy_testing_templates()
#
#
# Used soley in preview, searches for any templates checked out by the
# current user that are flagged as 'testing'.  If it finds any,
# deploys them in a temporary directory path.  The rest of the preview
# process will pick up these templates on an as-needed basis.
# (see template_search_path()
#
# Takes no arguments.  Requires that $ENV{REMOTE_USER} exists.
#

sub _deploy_testing_templates {

    my $self = shift;
    my $path;

    my $user_id = $ENV{REMOTE_USER} || croak __PACKAGE__ . ": 'REMOTE_USER' environment variable is not set!\n";

    # find any templates checked out by this user that are marked for testing.
    my @templates = Krang::Template->find(testing => 1, checked_out_by => $user_id);

    # if there are no templates, there's nothing left to do here.
    return unless (@templates);

    # there are templates - create a tempdir & deploy these bad boys.
    $path = tempdir( DIR => catdir(KrangRoot, 'tmp'));
    $self->{testing_template_path}{$user_id} = $path;

    foreach (@templates) {
        $self->_write_template(template => $_);
    }

}


#
# _undeploy_testing_templates()
#
# Removes the template files & temporary directory used by the current
# user for previewing the templates they have flagged for testing.
# This is a cleanup method, nothing more.
#
# Will croak if there's a system error or it cannot determine the user.
#
sub _undeploy_testing_templates {

    my $self = shift;

    my $user_id = $ENV{REMOTE_USER} || croak __PACKAGE__ . ": 'REMOTE_USER' environment variable is not set!\n";

    # there's no work if there's no dir.
    return unless exists($self->{testing_template_path}{$user_id});

    eval { rmtree($self->{testing_template_path}{$user_id}); };

    if ($@) { croak __PACKAGE__ . ": error removing temporary dir '$self->{testing_template_path}{$user_id}': $@"; }

    delete $self->{testing_template_path}{$user_id};

    return;
}

#
# $filename = _write_template(template => $template);
#
# Given a template, determines the full path of the template and writes it to disk.
# Will croak in the event of an error in the process.
# Returns the full path + filename if successful.
#

sub _write_template {

    my $self = shift;
    my %args = @_;

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

    return $file;

}



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
    my $article_output  = $story_element->publish(publisher => $self);

    my $category_output = $category_element->publish(publisher => $self);

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

    return $element->class()->filename() . $page . $element->class()->extension();

}


#
# @list = _add_to_publish_list($story)
#
# Internal method - takes Krang::Story object, adds it and it's related objects to the publish list.
#
sub _add_to_publish_list {
    my $self = shift;
    my $story = shift;
    my @publish_list = ();

    croak (__PACKAGE__ . ": 'stories' is not defined!") unless (defined($story));
    croak (__PACKAGE__ . ": 'stories' entry is not a Krang::Story object") unless ($story->isa('Krang::Story'));

    # add this story to the publish list.
    $self->{stories_to_be_published}{$story->story_id()} = 1;
    push @publish_list, $story;

    push @publish_list, $self->_process_linked_assets(story => $story);

    return @publish_list;
}



#
# _process_linked_assets(story => $story);
#
#
# This sub is the internal method used to walk the paths provided by
# the lists of linked assets that every story contains.  This walk is
# done recursively, the catch being that you do not want to add any
# linked asset to the publish list more than once, and you don't want
# to repeatedly process the same asset.
#
# This is a standard recursive walk - the internal hashes
# 'stories_to_be_published', 'stories_checked_for_links', and
# 'media_to_be_published' are used to make sure we're not getting
# trapped in a cycle.
#
sub _process_linked_assets {

    my $self = shift;
    my %args = @_;

    my @publish_list = ();

    croak (__PACKAGE__ . ": Missing argument 'story'!\n") unless (exists($args{story}));
    my $story = $args{story};

    foreach ($story->linked_stories()) {
        my $id = $_->story_id();
        # check to see if this story has been added to the publish list.
        next if (exists($self->{stories_to_be_published}{$id}));
        $self->{stories_to_be_published}{$id} = 1;
        push @publish_list, $_;
        # check to see if we've examined this story for additional links.
        next if (exists($self->{stories_checked_for_links}{$id}));
        $self->{stories_checked_for_links}{$id} = 1;
        # add whatever additional links it has to the list.
        push @publish_list, $self->_process_linked_assets(story => $_);
    }

    foreach ($story->linked_media()) {
        my $id = $_->media_id();
        # check to see if this media object has been added to the publish list.
        next if (exists($self->{media_to_be_published}{$id}));
        $self->{media_to_be_published}{$id} = 1;
        push @publish_list, $_;
    }

    return @publish_list;
}


#
# _build_story_all_categories(story => $story);
#
# Handles the process for publishing a story out over all its various categories.
# Used only in the publish process, not the preview process.
#
sub _build_story_all_categories {

    my $self = shift;
    my %args = @_;

    my $story = $args{story};

    # get story URLs.
    my @story_urls = $story->urls();
    my @categories = $story->categories();

    # log history
    add_history(object => $story, action => 'publish');

    # Categories & Story URLs are in identical order.  Move in lockstep w/ both of them.
    foreach (my $i = 0; $i <= $#categories; $i++) {
        debug("Publisher.pm: publishing story under URI='$story_urls[$i]'");

        $self->_build_story_single_category(story    => $story,
                                            category => $categories[$i],
                                            url      => $story_urls[$i]);
    }
}


#
# _build_story_single_category(story => $story, category => $category, url => $url);
#
# Used by both preview & publish processes.
#
# Given a story object, a category to publish under, and the url that
# indicates a final output path, run through the publish process for
# that story & category, and write out the resulting content under the
# filename that's indicated by the submitted url.
#
sub _build_story_single_category {

    my $self = shift;
    my %args = @_;

    my $story    = $args{story};
    my $category = $args{category};
    my $url      = $args{url};

    my $path;

    # create output path.
    if ($self->{is_publish}) {
        $path = catfile($category->site()->publish_path(), $url);
    } elsif ($self->{is_preview}) {
        $path = catfile($category->site()->preview_path(), $url);
    }

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
}



#
# $url = $pub->_write_out_media($media)
#
# Internal method for writing a media object to disk.  Returns media URL if successful.
#

sub _write_media {
    my $self = shift;
    my $media = shift;

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

    # check media back in.
    if ($media->checked_out()) { $media->checkin(); }

    # log event
    add_history(object => $media, action => 'publish');

    return $media->url();
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

    debug("Publisher.pm: wrote page '$output_filename'");

    return;
}


my $EBN =<<EOEBN;

This is a test of the emergency broadcast network.

Please stand by and await further instructions.

EOEBN
