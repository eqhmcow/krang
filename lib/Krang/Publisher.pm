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


  # unpublish a story, usually called from $story->delete
  $publisher->unpublish_story(story => $story);

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

  # unpublish a media object, usually called from $media->delete
  $publisher->unpublish_media(media => $media);

  # Get the list of related stories and media that will get published
  my $asset_list_ref = $publisher->get_publish_list(
                                                    story => [$story1, $story2]
                                                   );

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

  # Return the filename for a given page of the story being published.
  my $filename = $publisher->story_filename(page => $page_num);


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
use Time::Piece;
use Set::IntRange;

use Krang::Conf qw(KrangRoot instance);
use Krang::Story;
use Krang::Category;
use Krang::ElementClass;
use Krang::Template;
use Krang::History qw(add_history);
use Krang::DB qw(dbh);

use Krang::Log qw(debug info critical);


use constant PUBLISHER_RO => qw(is_publish is_preview story category);


use constant PAGE_BREAK         => "<<<<<<<<<<<<<<<<<< PAGE BREAK >>>>>>>>>>>>>>>>>>";
use constant CONTENT            => "<<<<<<<<<<<<<<<<<< CONTENT >>>>>>>>>>>>>>>>>>";
use constant ADDITIONAL_CONTENT => "KRANG_ADDITIONAL_CONTENT";

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


=item C<< $url = $publisher->preview_story(story => $story, category => $category, callback => \&onpreview) >>

Generates a story, saving it to the preview doc root on the filesystem.  Returns a URL to the story if successful, or will throw one of several potential Exceptions (potential issues: filesystem problems, exceptions thrown by other objects, anything else?) in the event something goes wrong.

category is an optional attribute.  By default, preview() will build a story based on the default category for the Story, otherwise it will preview the story in the supplied category.

As part of the publish process, all media and stories linked to by $story will be published to preview as well.

The optional parameter C<callback> may point to a subroutine which is
called when each object is published to the preview location.  It
recieves three named parameters - object, counter and total.

=cut

sub preview_story {

    my $self = shift;
    my %args = @_;
    my $callback = $args{callback};
    my $category;
    my $url;

    my $preview_url;

    my $story = $args{story} || croak __PACKAGE__ . ": missing required argument 'story'";

    # set internal mode - preview, not publish.
    $self->_mode_is_preview();

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


    # this is needed so that element templates don't get Krang's templates
    local $ENV{HTML_TEMPLATE_ROOT} = "";

    # deploy any templates flagged as testing for this user
    $self->_deploy_testing_templates();

    my $publish_list = $self->get_publish_list(story => [$story]);

    my $total = @$publish_list;
    my $counter = 0;
    my @paths;
    foreach my $object (@$publish_list) {

        $callback->(object  => $object,
                    total   => $total,
                    counter => $counter++) if $callback;

        if ($object->isa('Krang::Story')) {
            debug('Publisher.pm: Previewing story_id=' . $object->story_id());
            @paths = $self->_build_story_single_category(story    => $object,
                                                         category => $object->category,
                                                         url      => $object->preview_url()
                                                        );

            # fix up publish locations
            $self->_rectify_publish_locations(object  => $object,
                                              paths   => \@paths,
                                              preview => 1);

        } elsif ($object->isa('Krang::Media')) {
            debug('Publisher.pm: Previewing media_id=' . $object->media_id());
            $self->preview_media(media => $object);
        }
    }


    # cleanup - remove any testing templates.
    $self->_undeploy_testing_templates();

    $preview_url = "$url/" . $self->story_filename(story => $story);

    return $preview_url;
}

=item C<< $publisher->publish_story(story => $story, callback => \%onpublish) >>

Publishes a story to the live webserver document root, as set by publish_path.

When a story is published, it is published under all categories it is associated with (see Krang::Story->categories()).

As part of the publish process, all media and stories linked to by $story will be published as well.

If you do not care about related assets (WARNING - You want to care!), you can set the argument I<disable_related_assets> =>1

If the user attempts to publish content that is checked out by someone else, it will get skipped.

It is assumed that the UI will prevent a user from attempting to publish something when they do not have permissions.

The optional parameter C<callback> may point to a subroutine which is
called when each object is published.  It recieves three named
parameters - object, counter and total.

=cut

sub publish_story {

    my $self = shift;
    my %args = @_;

    # set internal mode - publish, not preview.
    $self->_mode_is_publish();

    # callbacks
    my $callback      = $args{callback};
    my $skip_callback = $args{skip_callback};

    my $publish_list;
    my $user_id = $ENV{REMOTE_USER};

    my $story = $args{story} || croak __PACKAGE__ . ": missing required argument 'story'";


    # this is needed so that element templates don't get Krang's templates
    local $ENV{HTML_TEMPLATE_ROOT} = "";

    # build the list of assets to publish.
    if ($args{disable_related_assets}) {
        debug(__PACKAGE__ . ": disabling related_assets checking for publish");
        if (ref $story eq 'ARRAY') {
            $publish_list = $story;
        } else {
            push @$publish_list, $story;
        }
    } else {
        $publish_list = $self->get_publish_list(%args);
    }

    my $total = @$publish_list;
    my $counter = 0;
    foreach my $object (@$publish_list) {
        if ($object->isa('Krang::Story')) {
            if ($object->checked_out) {
                if ($user_id != $object->checked_out_by) {
                    debug(__PACKAGE__ . ": skipping checked out story id=" . $object->story_id);
                    $skip_callback->(object => $object) if $skip_callback;
                    next;
                }
            }

            # don't make callbacks on media, that's handled in publish_media().
            $callback->(object  => $object,
                        total   => $total,
                        counter => $counter++) if $callback;

            my @paths = $self->_build_story_all_categories(story => $object);

            # fix up publish locations
            $self->_rectify_publish_locations(object => $object,
                                              paths  => \@paths,
                                              preview => 0);
            # mark as published.
            $object->mark_as_published();

        } elsif ($object->isa('Krang::Media')) {
            $self->publish_media(media => $object, %args);
            # publish_media() will mark the media object as published.
        }


    }
}


=item C<< $publisher->unpublish_story(story => $story) >>

Removes a story from its published locations.  Usually called by
$story->delete.  Affects both preview and publish locations.

B<NOTE:> The C<published>, C<publish_date> and C<published_version> attributes of the L<Krang::Story> object are not updated at this time.  If the UI ever supports Unpublish-Story functionality (currently, this is only called when a Krang::Story object is deleted), this work needs to be done.


=cut

sub unpublish_story {
    my ($self, %arg) = @_;
    my $dbh = dbh;
    my $story = $arg{story};

    # get location list, preview and publish
    my $paths = $dbh->selectcol_arrayref(
               "SELECT path FROM publish_story_location WHERE story_id = ?",
                                         undef, $story->story_id);

    # delete
    foreach my $path (@$paths) {
        next unless -f $path;
        unlink($path) or 
          croak("Unable to delete file '$path' during unpublish : $!");
    }

    # clean the table
    $dbh->do('DELETE FROM publish_story_location WHERE story_id = ?',
             undef, $story->story_id)
      if @$paths;
}

=item C<< $publisher->unpublish_media(media => $media) >>

Removes a media object from its published locations.  Usually called
by $media->delete.  Affects both preview and publish locations.

B<NOTE:> The C<published>, C<publish_date> and C<published_version> attributes of the L<Krang::Media> object are not updated at this time.  If the UI ever supports Unpublish-Media functionality (currently, this is only called when a Krang::Media object is deleted), this work needs to be done.


=cut

sub unpublish_media {
    my ($self, %arg) = @_;
    my $dbh = dbh;
    my $media = $arg{media};

    # get location list, preview and publish
    my $paths = $dbh->selectcol_arrayref(
               "SELECT path FROM publish_media_location WHERE media_id = ?",
                                         undef, $media->media_id);

    # delete
    foreach my $path (@$paths) {
        next unless -f $path;
        unlink($path) or 
          croak("Unable to delete file '$path' during unpublish : $!");
    }

    # clean the table
    $dbh->do('DELETE FROM publish_media_location WHERE media_id = ?',
             undef, $media->media_id)
      if @$paths;
}

=item C<< $url = $publisher->preview_media(media => $media) >>

Copies a media file out to the webserver doc root for the preview website.

Argument media is required.

Returns a url to the media file on the preview website if successful.

Will throw an exception if there are problems with the copy.

=cut

sub preview_media {

    my $self = shift;
    my %args = @_;

    croak (__PACKAGE__ . ": Missing argument 'media'!\n") unless (exists($args{media}));

    $self->_mode_is_preview();

    my $media = $args{media};

    return $self->_write_media(media => $media);

}


=item C<< $url = $publisher->publish_media(media => $media) >>

Copies a media file out to the webserver doc root for the publish website.

Attributes media and category are required.

Returns a url to the media file on the publish website if successful.

If the user attempts to publish content that is checked out by someone else, it will get skipped.

It is assumed that the UI will prevent a user from attempting to publish something when they do not have permissions.

Will throw an exception if there are problems with the copy.

=cut

sub publish_media {
    my $self = shift;
    my %args = @_;

    $self->_mode_is_publish();

    # callbacks
    my $callback      = $args{callback};
    my $skip_callback = $args{skip_callback};

    my $publish_list;

    my $user_id  = $ENV{REMOTE_USER};
    my @urls;

    croak (__PACKAGE__ . ": Missing argument 'media'!\n") unless (exists($args{media}));

    if (ref $args{media} eq 'ARRAY') {
        $publish_list = $args{media};
    } else {
        push @$publish_list, $args{media};
    }

    my $total = @$publish_list;
    my $counter = 0;

    foreach my $media_object (@$publish_list) {
        # cannot publish assets checked out by other users.
        if ($media_object->checked_out) {
            if ($user_id != $media_object->checked_out_by) {
                debug(__PACKAGE__ . ": skipping publish on checked out media object id=" . $media_object->media_id);
                $skip_callback->(object => $media_object) if $skip_callback;
                next;
            }
        }

        $callback->(object => $media_object,
                    total  => $total,
                    counter => $counter++) if $callback;

        push @urls, $self->_write_media(media => $media_object);

        # log event
        add_history(object => $media_object, action => 'publish');

        $media_object->mark_as_published();

    }


    return @urls;

}




=item C<< $publish_list_ref = $publisher->get_publish_list(story => $story, keep_asset_list = 1) >>

Returns the list of stories and media objects that will get published if publish_story(story => $story) is called.

The sub calls $story->linked_stories() and $story->linked_media() to generate the lists, recursively operating on the results generated by $story->linked_stories().

If successful, it will return lists of Krang::Story and Krang::Media objects that will get published along with $story.  At the absolute minimum (no linked stories or media), $stories->[0] will contain the originally submitted parameter $story.

The story parameter can either be a single Krang::Story object or a list or Krang::Story objects.

If you are going to be making multiple successive calls to get_publish_list(), and want to ensure that the returning asset list does not contain assets from previous calls, set the C<keep_asset_list> argument to 1.  Default behavior is to return all assets connected to the submitted stories.

=cut

sub get_publish_list {

    my $self = shift;
    my %args = @_;

    croak (__PACKAGE__ . ": Missing argument 'story'!") unless (exists($args{story}));

    my @publish_list;

    $self->_init_asset_lists();

    if (ref $args{story} eq 'ARRAY') {
        my $stories = $args{story};
        foreach my $story (@$stories) {
            push @publish_list, $self->_add_to_publish_list(story => $story);
        }
    } else {
        push @publish_list, $self->_add_to_publish_list(story => $args{story});
    }

    unless ($args{keep_asset_list}) {
        $self->_clear_asset_lists();
    }

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
    my $root = catdir(KrangRoot, 'data', 'templates', Krang::Conf->instance());

    if (exists($args{category})) {
        if (!defined($args{category})) {
            # if category arg is not defined, return root dir for instance.
            # (but check for template testing)
            if ($self->{is_preview} &&
                exists($self->{testing_template_path}{$user_id})) {
                return ($self->{testing_template_path}{$user_id}, $root);
            }
            return $root;
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

        push @paths, catfile($root, @subdirs);
        pop @subdirs;
    }

    # add root (possibly preview too) dir as well.
    if ($self->{is_preview} &&
        exists($self->{testing_template_path}{$user_id})) {
        push @paths, $self->{testing_template_path}{$user_id};
    }

    push @paths, $root;

    return @paths;

}


=item C<< $txt = $publisher->page_break() >>

Returns the tag used internally to mark the break between pages in a story.  When a multi-page story is assembled by the Krang::ElementClass element tree, it consists of a scaler containing these break tags.  The preview/publish process will split the scaler along those tags to create the individual pages of the story.

No exceptions to throw.

=cut

sub page_break {

    return PAGE_BREAK;

}


=item C<< $txt = $publisher->content() >>

Returns the tag used internally to mark the break between the top and bottom sections of a category page.  Once broken, the individual pages of a story will be placed in between the two halves, and the full HTML page will be assembled.

No exceptions to throw.

=cut

sub content {

    return CONTENT;

}


=item C<< $txt = $publisher->additional_content_block(filename => $filename, content => $html, use_category => 1); >>

Creates a formatted block of text from C<$html> that, during the final processing of output, will be split out from the rest of the content to be published, and will be written out to C<$filename>.

content and filename arguments are required.

C<use_category> is a boolean flag that tells Krang::Publisher whether or not to add the current L<Krang::Category> header/footer to the final output, as it will for the regular published output.  Defaults to true.

B<WARNING:> C<additional_content_block()> can be called as many times as desired, however it does not perform any sanity checks on C<filename> - if your output contains multiple blocks of additional content with identical filenames, they will overwrite eachother, and only the last one will remain.

=cut


sub additional_content_block {

    my $self = shift;
    my %args = @_;

    my $content  = $args{content}  || croak __PACKAGE__ . ": missing required argument 'content'";
    my $filename = $args{filename} || croak __PACKAGE__ . ": missing required argument 'filename'";
    my $use_category = exists($args{use_category}) ? $args{use_category} : 1;

    return qq{<${\ADDITIONAL_CONTENT} filename="$filename" use_category="$use_category">$content</${\ADDITIONAL_CONTENT}>};

}


=item C<< $filename = $publisher->story_filename(page => $page_num); >>

Returns the filename (B<NOT> the path + filename, just the filename) of the current story being published, given the page number.

page argument will default to 0 if not passed in.

arguments C<story> can be submitted if you want a filename for something other than what is currently being published.

=cut

sub story_filename {

    my $self = shift;
    my %args = @_;

    my $page     = $args{page} || 0;
    my $story    = $args{story} || $self->story;

    my $element = $story->element();

    if ($page == 0) { $page = ''; }

    return $element->class()->filename() . $page . $element->class()->extension();

}




=back

=head1 TODO

Pagination

=head1 SEE ALSO

L<Krang::ElementClass>, L<Krang::Category>, L<Krang::Media>

=cut

# $self->_rectify_publish_locations(object => $object, paths=>[], preview => 1)
#
# remove any dangling files previously published for this object and
# update the publish location data in the DB

sub _rectify_publish_locations {
    my $self = shift;
    my %arg = @_;
    my $object = $arg{object};
    my $paths  = $arg{paths} || [];
    my $preview = $arg{preview};
    my $type = $object->isa('Krang::Story') ? 'story' : 'media';
    my $id   = $type eq 'story' ? $object->story_id : $object->media_id;
    my $dbh  = dbh;

    # get old location list
    my $old_paths = $dbh->selectcol_arrayref(
       "SELECT path FROM publish_${type}_location 
        WHERE ${type}_id = ? AND preview = ?", undef, $id, $preview);

    # build hash of current paths
    my %cur = map { ($_,1) } @$paths;

    # delete any files that aren't part of the current set
    foreach my $old (@$old_paths) {
        next if $cur{$old};
        next unless -f $old;
        unlink($old) 
          or croak("Unable to delete extinct publish result '$old'.");
    }

    # write new paths to publish location table
    $dbh->do("DELETE FROM publish_${type}_location 
              WHERE ${type}_id = ? AND preview = ?", undef, $id, $preview);
    $dbh->do("INSERT INTO publish_${type}_location 
              (${type}_id,preview,path) VALUES ".join(',',('(?,?,?)')x@$paths),
             undef, map { ($id, $preview, $_) } @$paths)
      if @$paths;
}

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
# @paths = _build_story_all_categories(story => $story);
#
# Handles the process for publishing a story out over all its various categories.
# Used only in the publish process, not the preview process.
#
# Returns a list of file-system paths where the story was written

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
    my @paths;
    foreach (my $i = 0; $i <= $#categories; $i++) {
        debug("Publisher.pm: publishing story under URI='$story_urls[$i]'");

        push @paths, $self->_build_story_single_category(story    => $story,
                                            category => $categories[$i],
                                            url      => $story_urls[$i]);
    }
    return @paths;
}


#
# @paths = _build_story_single_category(story => $story, category => $category);
#
# Used by both preview & publish processes.
#
# Takes a Krang::Story and Krang::Category object.  Builds the story
# pages (and additional content, if it exists) for the story, and
# writes output to disk.
#
# Returns a list of files written to the filesystem (w/ complete path).
#

sub _build_story_single_category {

    my $self = shift;
    my %args = @_;

    my @paths;

    my $story    = $args{story}    || croak __PACKAGE__ . "missing argument 'story'";
    my $category = $args{category} || croak __PACKAGE__ . "missing argument 'category'";

    my $additional_content;

    my $output_path = $self->_determine_output_path(object => $story, category => $category);

    # set internal values for accessor methods to call.
    $self->{category} = $category;
    $self->{story}    = $story;

    # get root element for the story
    my $story_element    = $story->element();
    my $category_element = $category->element();

    # get the HTML content for the story & category..
    my $article_output  = $story_element->publish(publisher => $self);
    my $category_output = $category_element->publish(publisher => $self);

    # break the category into header & footer.
    my ($cat_header, $cat_footer) = split(/${\CONTENT}/, $category_output, 2);

    # parse out additional content
    ($additional_content, $article_output) = $self->_parse_additional_content(text => $article_output);

    # write additional content to disk
    foreach my $block (@$additional_content) {
        my $content = $block->{content};
        if ($block->{use_category}) {
            $content = $cat_header . $content . $cat_footer;
        }
        push @paths, $self->_write_page(data     => $content,
                                        filename => $block->{filename},
                                        story_id => $story->story_id,
                                        path     => $output_path
                                       );

    }

    # break the story into pages
    my @article_pages = split(/${\PAGE_BREAK}/, $article_output);

    # chuck the last page if it's only whitespace.
    if ($article_pages[$#article_pages] =~ /^\s*$/) {
        pop @article_pages;
    }


    my @pages;
    # assemble the components.
    foreach (@article_pages) {
        my $page = $cat_header . $_ . $cat_footer;
        push @pages, $page
    }

    push @paths, $self->_write_story(story => $story, pages => \@pages, path => $output_path);

    return @paths;
}




##################################################
##
## Asset Link Checking
##

#
# @list = _add_to_publish_list(story => $story)
#
# Internal method - takes Krang::Story object, adds it and it's related objects to the publish list.
#
sub _add_to_publish_list {

    my $self = shift;
    my %args = @_;
    my @publish_list = ();

    my $story    = $args{story};
    my $story_id = $story->story_id();

    croak (__PACKAGE__ . ": 'stories' is not defined!") unless (defined($story));
    croak (__PACKAGE__ . ": 'stories' entry is not a Krang::Story object") unless ($story->isa('Krang::Story'));

    # add this story to the publish list.
    unless ($self->{story_publish_set}->contains($story_id)) {
        $self->{story_publish_set}->Bit_On($story_id);
        push @publish_list, $story;
    }

    # check to see if this story needs to be checked for related assets.
    unless ($self->{checked_links_set}->contains($story_id)) {
        $self->{checked_links_set}->Bit_On($story_id);
        push @publish_list, $self->_process_linked_assets(story => $story);
    }

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
# This is a standard recursive walk - the internal integer sets
# 'story_publish_set', 'checked_links_set', and 'media_publish_set'
# are used to make sure we're not getting trapped in a cycle.
#
sub _process_linked_assets {

    my $self = shift;
    my %args = @_;

    my @publish_list = ();

    croak (__PACKAGE__ . ": Missing argument 'story'!\n") unless (exists($args{story}));
    my $story = $args{story};

    foreach ($story->linked_stories()) {
        my $id = $_->story_id();
        # 1) add to publish list if not already on the list
        next if ($self->{story_publish_set}->contains($id));
        $self->{story_publish_set}->Bit_On($id);
        push @publish_list, $_;

        # 2) check for related assets if not already on the list.
        next if ($self->{checked_links_set}->contains($id));
        $self->{checked_links_set}->Bit_On($id);
        push @publish_list, $self->_process_linked_assets(story => $_);
    }

    # 1) add asset to the list if not already on it.
    foreach ($story->linked_media()) {
        my $id = $_->media_id();

        next if ($self->{media_publish_set}->contains($id));
        $self->{media_publish_set}->Bit_On($id);
        push @publish_list, $_;
    }

    return @publish_list;
}


#
# _init_asset_lists()
#
# Set up the internally-maintained lists of asset IDs,
# these lists are used by get_publish_list to determine which assets are
# going to get published.
#
# Note - Set::IntRange is being used as an efficient method for storing
# potentially large sets of integers.
#

sub _init_asset_lists {

    my $self = shift;

    foreach (qw(story_publish_set media_publish_set checked_links_set)) {
        $self->{$_} = Set::IntRange->new(0, 4194304) unless (exists ($self->{$_}));
    }
}

#
# _clear_asset_lists()
#
# Nukes all content in the asset lists.
#
sub _clear_asset_lists {

    my $self = shift;

    foreach (qw(story_publish_set media_publish_set checked_links_set)) {
        $self->{$_}->Empty();
    }
}


############################################################
#
# ADDITIONAL CONTENT METHODS
#

#
# (\@additional_output, $article) = $self->_parse_additional_content(text => $article)
#
# Returns a listref of hashes containing additional content associated w/ story.
# Also returns article text minus additional content text.
#

sub _parse_additional_content {

    my $self = shift;
    my %args = @_;

    my $article = $args{text} || croak __PACKAGE__ . ": missing argument 'text'";

    my @content;

    while ($article =~ s/<${\ADDITIONAL_CONTENT}\s*filename="([^\"]+)"\s*use_category="([^\"]+)[^>]+>(.+?)<\/${\ADDITIONAL_CONTENT}>//s) {
        my %entry = (filename => $1,
                     use_category => $2,
                     content => $3);

        push @content, \%entry;
    }

    return (\@content, $article);
}


##################################################
##
## Output
##

#
# $url = $pub->_write_media($media)
#
# Internal method for writing a media object to disk.  Returns media URL if successful.
#

sub _write_media {
    my $self = shift;
    my %args = @_;

    my $media = $args{media} || croak __PACKAGE__ . ": missing argument 'media'";

    my $internal_path = $media->file_path();

    my $output_path = $self->_determine_output_path(object => $media);

    $output_path =~ /^(.*\/)[^\/]+/;
    my $dir_path = $1;

    # make sure the output dir exists
    eval {mkpath($dir_path, 0, 0755); };
    if ($@) {
        Krang::Publisher::FileWriteError->throw(message => 'Could not create output directory',
                                                destination => $dir_path,
                                                system_error => $@);
    }

    # copy file out to the production path
    unless (copy($internal_path, $output_path)) {
        Krang::Publisher::FileWriteError->throw(message  => 'Could not copy media file',
                                                media_id => $media->media_id(),
                                                source   => $internal_path,
                                                destination => $output_path,
                                                system_error => $!
                                               );
    }

    # fix up output location
    $self->_rectify_publish_locations(object => $media,
                                      paths  => [ $output_path ],
                                      preview => $self->{is_preview});

    # return URL
    $self->{is_preview} ? return $media->preview_url : return $media->url;

}


#
# @filenames = _write_story(story => $story_obj, path => $output_path, pages => \@story_pages);
#
# Given a Krang::Story object and a list of pages comprising the published
# version of the object, write the pages to the filesystem.
#
# Returns the list of files written out.
#

sub _write_story {

    my $self = shift;
    my %args = @_;

    my $story       = $args{story} || croak __PACKAGE__ . ": missing argument 'story'";
    my $pages       = $args{pages} || croak __PACKAGE__ . ": missing argument 'pages'";
    my $output_path = $args{path}  || croak __PACKAGE__ . ": missing argument 'path'";

    my @created_files;


    for (my $page_num = 0; $page_num < @$pages; $page_num++) {

        my $filename = $self->story_filename(story => $story, page => $page_num);

        my $output_filename = $self->_write_page(path     => $output_path,
                                                 filename => $filename,
                                                 story_id => $story->story_id,
                                                 data     => $pages->[$page_num]);

        push(@created_files, $output_filename);
    }

    return @created_files;

}

#
# $output_filename = _write_page(path => $path, filename => $filename, data => $content, story_id => $id)
#
# Writes the content in $data to $path/$filename.
#
# Will croak if it cannot determine the filename, or
# cannot write to the filesystem.
#
# Returns the full path to the file written.
#
sub _write_page {

    my $self = shift;
    my %args = @_;

    foreach (qw(path filename)) {
        croak __PACKAGE__ . ": missing parameter '$_'.\n" unless defined ($args{$_});
    }

    eval { mkpath($args{path}, 0, 0755); };
    if ($@) {
        Krang::Publisher::FileWriteError->throw(message      => "Could not create directory '$args{path}'",
                                                destination  => $args{path},
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

    return $output_filename;
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
        Krang::Publisher::FileWriteError->throw(message      => 'Could not create publish directory',
                                                destination  => $path,
                                                system_error => $@);
    }


    my $file = catfile($path, $template->filename());

    # write out file
    my $fh = IO::File->new(">$file") or
      Krang::Publisher::FileWriteError->throw(message      => 'Cannot deploy template',
                                              template_id  => $id,
                                              destination  => $file,
                                              system_error => $!);
    $fh->print($template->{content});
    $fh->close();

    return $file;

}


#
# $path = $self->_determine_output_path(object => $object, category => $category);
#
# Returns preview/publish path depending on publish mode.
#

sub _determine_output_path {
    my $self = shift;
    my %args = @_;

    my $object = $args{object} || croak __PACKAGE__ . ": missing argument 'object'";
    my $output_path;

    if ($self->{is_publish}) {
        if ($object->isa('Krang::Story')) {
            my $category = $args{category} || croak __PACKAGE__ . ": missing argument 'category'";
            $output_path = $object->publish_path(category => $category);
        } else {
            $output_path = $object->publish_path();
        }
    } elsif ($self->{is_preview}) {
        $output_path = $object->preview_path();
    } else {
        croak __PACKAGE__ . ": Cannot determine preview/publish mode";
    }

    return $output_path;
}

############################################################
#
# MODES -
#
# The internal hash keys is_preview and is_publish are checked in a lot of places
# quick subroutines to cut down on issues.
#

sub _mode_is_preview {

    my $self = shift;

    $self->{is_preview} = 1;
    $self->{is_publish} = 0;

}

sub _mode_is_publish {

    my $self = shift;

    $self->{is_preview} = 0;
    $self->{is_publish} = 1;

}

my $EBN =<<EOEBN;

This is a test of the emergency broadcast network.

Please stand by and await further instructions.

EOEBN
