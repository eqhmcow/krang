package Krang::Publisher;

=head1 NAME

Krang::Publisher - Center of the Publishing Universe.

=head1 SYNOPSIS

  use Krang::ClassLoader 'Publisher';

  my $publisher = new pkg('Publisher')();


  # Publish a list of stories to the preview path.
  # returns preview URL of first story in the list.
  my $url = $publisher->preview_story(story => \@stories);


  # Publish a list of stories to the publish path.
  $publisher->publish_story(story => \@stories);


  # unpublish a story, usually called from $story->delete
  $publisher->unpublish_story(story => $story);

  # Publish a media object to the preview path.
  # Returns the media URL if successful.
  $url = $publisher->preview_media(media => $media);

  # Publish a media object to the preview path.
  # Returns the media URL if successful.
  $url = $publisher->publish_media(media => $media);

  # unpublish a media object, usually called from $media->delete
  $publisher->unpublish_media(media => $media);

  # Get the list of related stories and media that will get published
  my $asset_list = $publisher->asset_list(story => [$story1, $story2]);

  # Place a Krang::Template template into the production path, to be
  # used when publishing.
  $publisher->deploy_template(template => $template);

  # Remove a template from the production path.
  $publisher->undeploy_template(template => $template);

  # Returns the mark used internally to break content into pages.
  my $break_txt = $publisher->PAGE_BREAK();

  # Return the Krang::Story object of the story currently being published.
  my $story = $publisher->story();

  # Return the Krang::Category object for the current category of the
  # story being published.
  my $category = $publisher->category();

  # Return the filename for a given page of the story being published.
  my $filename = $publisher->story_filename(page => $page_num);

  # determine if we're in preview mode or publish mode.
  $bool = $publisher->is_preview();
  $bool = $publisher->is_publish();

  # check to see if an object will be published, given its current state
  $bool = $publisher->test_publish_status(object => $story, mode => 'publish');

=head1 DESCRIPTION

Krang::Publisher is responsible for coordinating the various
components that make up a Story (Elements, Media, Categories), and
putting them all together, out on the filesystem, for the world + dog
to see.  The publish process will result in either 'preview' or
'publish' output - content-wise, they are indistinguishable.

In both the preview and publish process, stories are checked for
related media (see L<Krang::Story>->linked_media()).  Media objects
will be copied into the proper output directory as part of the build
process.

Unless C<version_check> is turned off, all related assets will compare
C<version()> with C<preview_version()> or C<published_version()>, to see
if the currently live version (in either preview or publish, depending
on the mode) is the latest saved version.  If so, the asset will not
be published, though it will be checked for additional related assets
to publish.

See L<Krang::ElementClass::TopLevel>->force_republish() to bypass the
C<version_check> functionality.

In the publish (but not preview) process, stories will also be checked
for linked stories (see L<Krang::Story>->linked_stories()).  Any
linked-to stories will be checked for publish status, and will be
published if they are marked as unpublished.

=cut

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Carp;

use File::Spec::Functions;
use File::Copy qw(copy);
use File::Path;
use File::Temp qw(tempdir);
use Time::Piece;

use Krang::ClassLoader Conf => qw(KrangRoot instance PreviewSSL EnablePreviewEditor IgnorePreviewRelatedStoryAssets IgnorePreviewRelatedMediaAssets);
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Template';
use Krang::ClassLoader 'IO';
use Krang::ClassLoader History => qw(add_history);
use Krang::ClassLoader DB      => qw(dbh);
use Krang::ClassLoader Element => qw(foreach_element);
use Krang::ClassLoader Log => qw(debug info critical);

use constant PUBLISHER_RO       => qw(is_publish is_preview story category);
use constant PAGE_BREAK         => "<<<<<<<<<<<<<<<<<< PAGE BREAK >>>>>>>>>>>>>>>>>>";
use constant CONTENT            => "<<<<<<<<<<<<<<<<<< CONTENT >>>>>>>>>>>>>>>>>>";
use constant ADDITIONAL_CONTENT => "KRANG_ADDITIONAL_CONTENT";

use Exception::Class
  'Krang::Publisher::FileWriteError' =>
  {fields => ['story_id', 'media_id', 'template_id', 'source', 'destination', 'system_error']},
  'Krang::Publisher::ZeroSizeOutput' => {fields => ['story_id', 'category_url', 'story_class']};

use Krang::ClassLoader MethodMaker => (
    new_with_init => 'new',
    new_hash_init => 'hash_init',
    get           => [PUBLISHER_RO]
);

=head1 INTERFACE

=head2 FIELDS

Access to fields for this object are provided by
Krang::MethodMaker. All fields are accessible in a B<read-only>
fashion.  The value of fields can be obtained in the following
fashion:

  $value = $publisher->field_name();

The available fields for a publish object are:

=over

=item * is_preview

Returns a 1 if the current publish run is in preview-mode, 0
otherwise.

=item * is_publish

Returns a 1 if the current publish run is in publish-mode (e.g. going
live), 0 otherwise.

=item * category

Returns a Krang::Category object for the category currently being
published.

=item * story

Returns a Krang::Story object for the Story currently being published.

=back

=cut

=head2 METHODS

=over

=item C<< $publisher = Krang::Publisher->new(); >>

Creates a new Krang::Publisher object.  No parameters are needed at
this time.

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

=item C<< $url = $publisher->preview_story(story => $story) >>

Generates a story, saving it to the preview doc root on the
filesystem.  Returns a URL to the story if successful, or will throw
one of several potential Exceptions (potential issues: filesystem
problems, exceptions thrown by other objects, anything else?) in the
event something goes wrong.

Arguments:

=over

=item * C<story>

A single L<Krang::Story> object.

=item * C<unsaved>

defaults to 0.  If C<unsaved> is true,
L<Krang::Story>->preview_version will be set to -1.  What this does
is force a republish of the story object to the preview path the next
time the object comes up as a related object to a story being
previewed.

As part of the publish process, all media and stories linked to by
C<$story> will be examined.  If the current version of each object has
not been published to preview, it will be.  If the object has been
previewed previously, it will be skipped.


=item * C<version_check>

Defaults to 1.  When true, it checks all related stories and media to
see if the current version has been published previously to the
preview path, skipping those that have.  When false, it will publish
all related assets, regardless of whether or not the current version
has been published to preview before.


=item * C<remember_asset_list>

Boolean, defaults to false.

If true, the C<Krang::Publisher> object will remember these media
objects, and will skip re-publishing them if they come up again
(e.g. if linked to a story being published).

This only affects successive publish calls to a single
C<Krang::Publisher> object.  See C<bin/krang_publish> for an example
of this functionality being used.

=item * C<callback>

The optional parameter C<callback> will point to a subroutine which is
called when each object is published to the preview location.  It
recieves three named parameters:

=over

=item C<object>

The affected object.

=item C<counter>

The index of the current object in the list of objects being published.

=item C<total>.

The total number of objects being published.

=back

=back

=cut

sub preview_story {

    my $self = shift;
    my %args = @_;

    # set internal mode - preview, not publish.
    $self->_set_preview_mode();

    # this is needed so that element templates don't get Krang's templates
    local $ENV{HTML_TEMPLATE_ROOT} = "";

    my $story           = $args{story} || croak __PACKAGE__ . ": missing required argument 'story'";
    my $callback        = $args{callback};
    my $unsaved         = (exists($args{unsaved})) ? $args{unsaved} : 0;
    my $version_check   = (exists($args{version_check})) ? $args{version_check} : 1;
    my $keep_asset_list = $args{remember_asset_list} || 0;

    # deploy any templates flagged as testing for this user
    $self->_deploy_testing_templates();

    my $publish_list = $self->asset_list(
        story         => [$story],
        version_check => $version_check
    );

    $self->_process_preview_assets(
        publish_list => $publish_list,
        callback     => $callback,
        unsaved      => $unsaved,
        story        => $story
    );

    # cleanup - remove any testing templates.
    $self->_undeploy_testing_templates();

    $self->_clear_asset_lists() unless ($keep_asset_list);

    my $preview_url = catfile($story->preview_url, $self->story_filename(story => $story));

    return $preview_url;
}

=item C<< $publisher->publish_story(story => $story, callback => \%onpublish) >>

Publishes a story to the live webserver document root, as set by
publish_path.

When a story is published, it is published under all categories it is
associated with (see Krang::Story->categories()).

As part of the publish process, all media and stories linked to by
$story will be examined.  For each of these objects, if the latest
version has not yet been published, it will be.  If the current
version has been published, it will be skipped (though the objects
links will also be checked).

If you do not care about related assets (WARNING - You want to care!),
you can set the argument I<disable_related_assets> =>1

If the user attempts to publish an object that is checked out by
someone else, it will get skipped.

It is assumed that the UI will prevent a user from attempting to
publish something when they do not have permissions.  The only
access-control issues that will come up here would involve filesystem
permissions.

Arguments:

=over

=item * C<story>

Either a single L<Krang::Story> object, or a reference to an array of
L<Krang::Story> objects.


=item * C<disable_related_assets>

Defaults to 0.  If true, no link-checking is done, only the items
passed in as part of the C<story> argument are published.


=item * C<version_check>

Defaults to 1.  When true, it checks all related stories and media to
see if the current version has been published previously, skipping
those that have.  When false, it will publish all related assets,
regardless of whether or not the current version has been published
before.

=item * C<maintain_versions>

Defaults to 0. If true, will re-publish the last-published
version of each asset rather than the latest version.

=item * C<remember_asset_list>

Boolean, defaults to false.

If true, the C<Krang::Publisher> object will remember these media
objects, and will skip re-publishing them if they come up again
(e.g. if linked to a story being published).

This only affects successive publish calls to a single
C<Krang::Publisher> object.  See C<bin/krang_publish> for an example
of this functionality being used.


=item * C<callback>

The optional parameter C<callback> will point to a subroutine which is
called when each object is published to the preview location.  It
recieves three named parameters:

=over

=item C<object>

The affected object.

=item C<counter>

The index of the current object in the list of objects being published.

=item C<total>.

The total number of objects being published.

=back


=item * C<skip_callback>

The optional parameter C<skip_callback> is a pointer to a subroutine
which is called whenever an object is skipped during the publish
process, for whatever reason.  It takes four named parameters:

=over

=item C<object>

The object being skipped during the publish run.

=item C<error>

The type of error.  C<output_error>, C<checked_out>, and a number of
internal exceptions are the current set.

=item C<path>

The location on the filesystem where the object was to be published to.

=item C<error_msg>

A text message explaining the error in more detail.


=back

=back

=cut

sub publish_story {

    my $self = shift;
    my %args = @_;

    # set internal mode - publish, not preview.
    $self->_set_publish_mode();

    my $story = $args{story} || croak __PACKAGE__ . ": missing required argument 'story'";
    my $unsaved           = (exists($args{unsaved}))           ? $args{unsaved}           : 0;
    my $version_check     = (exists($args{version_check}))     ? $args{version_check}     : 1;
    my $maintain_versions = (exists($args{maintain_versions})) ? $args{maintain_versions} : 0;

    # callbacks
    my $callback      = $args{callback};
    my $skip_callback = $args{skip_callback};

    my $no_related_check =
      (exists($args{disable_related_assets})) ? $args{disable_related_assets} : 0;
    my $keep_asset_list = $args{remember_asset_list} || 0;
    my $user_id = $ENV{REMOTE_USER};
    my $publish_list;

    # this is needed so that element templates don't get Krang's templates
    local $ENV{HTML_TEMPLATE_ROOT} = "";

    # build the list of assets to publish.
    if ($no_related_check) {
        debug(__PACKAGE__ . ": disabling related_assets checking for publish");
        if (ref $story eq 'ARRAY') {
            $publish_list = $story;
        } else {
            push @$publish_list, $story;
        }

        # normally _build_asset_list() handles the 'maintain_version' option, so
        # when running in 'disable_related_assets' mode we need to handle it here
        if ($maintain_versions) {
            my @stories;
            foreach my $s (@$publish_list) {
                if ($s->checked_out && ($s->checked_out_by != $user_id)) {

                    # if story is checked out to another user, it shouldn't get published anyway
                    # (doing so would clear the checked-out flag), so we don't get old version
                    push @stories, $s;
                } else {

                    # story is not checked out, so we grab last-published version (if any)
                    my $v = $s->published_version;
                    next unless $v;
                    if ($v == $s->version) {
                        push @stories, $s;
                    } else {
                        push @stories, pkg('Story')->find(story_id => $s->story_id, version => $v);
                    }
                }
            }
            $publish_list = \@stories;
        }
    } else {
        $publish_list = $self->asset_list(
            story             => $story,
            version_check     => $version_check,
            maintain_versions => $maintain_versions
        );
    }

    $self->_process_assets(
        publish_list        => $publish_list,
        skip_callback       => $skip_callback,
        callback            => $callback,
        user_id             => $user_id,
        remember_asset_list => $keep_asset_list
    ) if scalar(@$publish_list);

    $self->_clear_asset_lists() unless ($keep_asset_list);
}

=item C<< $publisher->unpublish_story(story => $story) >>

Removes a story from its published locations.  Usually called by
$story->delete.  Affects both preview and publish locations.

The C<published>, C<publish_date> and C<published_version>
attributes of the L<Krang::Story> object all removed and set to C<undef>.

=cut

sub unpublish_story {
    my ($self, %arg) = @_;
    my $dbh = dbh;
    my $story = $arg{story} || croak __PACKAGE__ . ": missing required argument 'story'";

    # get location list, preview and publish
    my $paths =
      $dbh->selectcol_arrayref("SELECT path FROM publish_story_location WHERE story_id = ?",
        undef, $story->story_id);

    # neither published nor previewed?
    return unless @$paths;

    # delete story in publish and/or preview dir(s)
    foreach my $path (@$paths) {
        next unless -f $path;

        # make sure this path isn't claimed by another story
        my ($claimed) =
          $dbh->selectrow_array(
            "SELECT 1 FROM publish_story_location WHERE path = ? AND story_id != ?",
            undef, $path, $story->story_id);

        next if $claimed;

        unlink($path)
          or croak("Unable to delete file '$path' during unpublish : $!");
    }

    # delete the dir itself - if it's empty
    my @cats = $story->categories();
    foreach my $cat (@cats) {

        # only if the story isn't a "Cover"
        next if ($cat->url eq $story->url);

        my %path_args = (category => $cat);

        for my $dir ($story->preview_path(%path_args), $story->publish_path(%path_args)) {
            next unless -d $dir;

            opendir(DIRH, $dir)
              or croak("Unable to open directory $dir during unpublish: $!");
            my @files = grep { not /^\.\.?$/ } readdir(DIRH);
            closedir(DIRH);
            next if @files;

            rmdir($dir)
              or croak("Unable to delete dir '$dir' during unpublish : $!");
        }
    }

    # clean the table
    $dbh->do('DELETE FROM publish_story_location WHERE story_id = ?', undef, $story->story_id);

    # unset the publish flags
    $story->{published_version} = undef;
    $story->{publish_date}      = undef;
    $dbh->do(
        'UPDATE story SET published_version = ?, publish_date = ?  WHERE story_id = ?',
        undef,
        $story->{published_version},
        $story->{publish_date},
        $story->{story_id}
    );
}

=item C<< $publisher->unpublish_media(media => $media) >>

Removes a media object from its published locations.  Usually called
by $media->delete.  Affects both preview and publish locations.

The C<published>, C<publish_date> and C<published_version>
attributes of the L<Krang::Media> object are reset to C<undef>.

=cut

sub unpublish_media {
    my ($self, %arg) = @_;
    my $dbh = dbh;
    my $media = $arg{media} || croak __PACKAGE__ . ": missing required argument 'media'";

    # get location list, preview and publish
    my $paths =
      $dbh->selectcol_arrayref("SELECT path FROM publish_media_location WHERE media_id = ?",
        undef, $media->media_id);

    # delete
    foreach my $path (@$paths) {
        next unless -f $path;
        unlink($path)
          or croak("Unable to delete file '$path' during unpublish : $!");
    }

    # clean the table
    $dbh->do('DELETE FROM publish_media_location WHERE media_id = ?', undef, $media->media_id)
      if @$paths;

    # unset the publish flags
    $media->{published_version} = undef;
    $media->{publish_date}      = undef;
    $media->{published}         = 0;

    # update the DB.
    $dbh->do(
        'UPDATE media
              SET published_version = ?,
                  publish_date = ?,
                  published = 0
              WHERE media_id = ?',
        undef,
        $media->{published_version},
        $media->{publish_date},
        $media->{media_id}
    );

    # if media element has an unpublish() method, call it
    if ($media->element->class->can('unpublish')) {
        $media->element->class->unpublish(
            publisher => $self,
            media     => $media,
            element   => $media->element
        );
    }
}

=item C<< $url = $publisher->preview_media(media => $media, unsaved => 1) >>

Copies a media file out to the webserver doc root for the preview
website.

Arguments:

=over

=item * C<media>

Required.  The L<Krang::Media> object being previewed.

=item * C<unsaved>

Optional, defaults to 0.  If C<unsaved> is true,
L<<Krang::Media->preview_version>> will be set to -1.  What this does
is force a republish of the media object to the preview path the next
time the object comes up as a related object to a story being
previewed.

=item * C<remember_asset_list>

Boolean, defaults to false.

If true, the C<Krang::Publisher> object will remember these media
objects, and will skip re-publishing them if they come up again
(e.g. if linked to a story being published).

This only affects successive publish calls to a single
C<Krang::Publisher> object.  See C<bin/krang_publish> for an example
of this functionality being used.


=back

Returns a url to the media file on the preview website if successful.

Will throw an exception if there are problems with the copy.

=cut

sub preview_media {

    my $self = shift;
    my %args = @_;

    $self->_set_preview_mode();

    my $keep_asset_list = $args{remember_asset_list} || 0;

    my $media = $args{media} || croak __PACKAGE__ . ": Missing argument 'media'!\n";
    my $unsaved = (exists($args{unsaved})) ? $args{unsaved} : 0;

    # add it to the asset list
    unless ($unsaved) {
        $self->_mark_asset(object => $media);
    }

    $media->mark_as_previewed(unsaved => $unsaved);

    $self->_clear_asset_lists() unless ($keep_asset_list);

    return $self->_write_media(media => $media);

}

=item C<< $url = $publisher->publish_media(media => $media) >>

Copies a media file out to the webserver doc root for the publish website.

Arguments:

=over

=item * C<media>

Required.  The Krang::Media object being published.

=item * C<remember_asset_list>

Boolean, defaults to false.

If true, the C<Krang::Publisher> object will remember these media
objects, and will skip re-publishing them if they come up again
(e.g. if linked to a story being published).

This only affects successive publish calls to a single
C<Krang::Publisher> object.  See C<bin/krang_publish> for an example
of this functionality being used.

=item * C<maintain_versions>

Defaults to 0. If true, we will re-publish the last-published
version of the media (if any) rather than the latest.

=back

Returns a url to the media file on the publish website if successful.

If the user attempts to publish content that is checked out by someone
else, it will get skipped.

It is assumed that the UI will prevent a user from attempting to
publish something when they do not have permissions.

Will throw an exception if there are problems with the copy.

=cut

sub publish_media {
    my $self = shift;
    my %args = @_;

    $self->_set_publish_mode();

    # callbacks
    my $callback      = $args{callback};
    my $skip_callback = $args{skip_callback};

    my $maintain_versions = $args{maintain_versions}   || 0;
    my $keep_asset_list   = $args{remember_asset_list} || 0;

    my $publish_list;

    my $user_id = $ENV{REMOTE_USER};
    my @urls;

    croak(__PACKAGE__ . ": Missing argument 'media'!\n") unless (exists($args{media}));

    if (ref $args{media} eq 'ARRAY') {
        $publish_list = $args{media};
    } else {
        push @$publish_list, $args{media};
    }

    my $total   = @$publish_list;
    my $counter = 0;

    foreach my $media_object (@$publish_list) {

        # make a note in the asset list.
        my $ok = $self->_mark_asset(object => $media_object);

        # cannot publish assets checked out by other users.
        if ($media_object->checked_out) {
            if ($user_id != $media_object->checked_out_by) {
                debug(  __PACKAGE__
                      . ": skipping publish on checked out media object id="
                      . $media_object->media_id);
                $skip_callback->(object => $media_object, error => 'checked_out') if $skip_callback;
                next;
            }
        }

        # if requested, re-publish last-published (instead of latest) version
        if ($maintain_versions) {
            my $v = $media_object->published_version;
            next unless $v;
            if ($v != $media_object->version) {
                my ($media_object) =
                  pkg('Media')->find(media_id => $media_object->media_id, version => $v);
            }
        }

        eval {
            push @urls, $self->_write_media(media => $media_object);

            # log event
            add_history(object => $media_object, action => 'publish');

            $media_object->mark_as_published();

            $callback->(
                object  => $media_object,
                total   => $total,
                counter => $counter++
            ) if $callback;
        };

        if ($@) {
            if ($skip_callback) {
                if (ref $@ && $@->isa('Krang::Publisher::FileWriteError')) {
                    $skip_callback->(
                        object    => $media_object,
                        error     => 'output_error',
                        path      => $@->destination,
                        error_msg => $@->system_error
                    );
                } else {

                    # call generic skip_callback.
                    $skip_callback->(object => $media_object, error => ref $@ ? $@->isa : $@);
                }
            }

            # the skip_callback is not used by the CGIs - re-propegate the error so the UI
            # can handle it.
            else {
                die($@);
            }
        }

    }

    $self->_clear_asset_lists() unless ($keep_asset_list);

    return @urls;

}

=item C<< $asset_list = $publisher->asset_list(story => $story) >>

Returns the list of stories and media objects that will get published
if either L<publish_story()> or L<preview_story()> is called.

The sub calls $story->linked_stories() and $story->linked_media() to
generate the lists, recursively operating on the results generated by
$story->linked_stories().

If successful, it will return lists of L<Krang::Story> and
L<Krang::Media> objects that will get published along with $story.  At
the absolute minimum (no linked stories or media), $stories->[0] will
contain the originally submitted parameter $story.

Arguments:

=over

=item * C<story>

The story parameter can either be a single L<Krang::Story> object or a
list of L<Krang::Story> objects.

=item * C<keep_asset_list>

Defaults to false.  If true, the internal list of checked stories is
not cleared upon completion.  If you are going to be making multiple
successive calls to asset_list(), and want to ensure that the
returning asset list does not contain assets from previous calls, set
to true.

=item * C<mode>

Optional.  Either 'preview' or 'publish'.  If not set, checks to see
if either C<is_preview()> or C<is_publish> is true.  If neither are
true, will croak.


=item * C<version_check>

Defaults to true.  If true, every related asset will be checked to see
if either C<< $object->preview_version() >> or
C<< $object->published_version() >> (depending on C<mode> above) is equal
to C<< $object->version() >>.  If so, it won't be published, but its'
related assets will still be checked.

Setting C<version_check> to 0 (false) will result in the original
Krang behavior - all related content will be published, regardless of
versioning.

This addition is a performance improvement - the purpose is to keep
from publishing content that has not changed since the last
publishing.

=item * C<maintain_versions>

Defaults to 0. If true (and in publish mode), we will build a list of the 
last-published version of each asset (if any) rather than the latest version.

=back

=cut

sub asset_list {

    my $self = shift;
    my %args = @_;

    my $story = $args{story} || croak __PACKAGE__ . ": Missing parameter 'story'";
    my $mode = $args{mode};

    #    my $keep_list     = $args{keep_asset_list} || 0;
    #    my $keep_list = 0;
    my $version_check = (exists($args{version_check})) ? $args{version_check} : 1;

    # check publish mode.
    if ($mode) {
        if    ($mode eq 'preview') { $self->_set_preview_mode(); }
        elsif ($mode eq 'publish') { $self->_set_publish_mode(); }
        else                       { croak __PACKAGE__ . ": unknown output mode '$mode'\n"; }
    } else {
        if    ($self->is_preview()) { $mode = 'preview'; }
        elsif ($self->is_publish()) { $mode = 'publish'; }
        else {
            croak "Publish mode unknown.  Set the 'mode' argument'";
        }
    }

    # consider story-specific logic to determine whether the story
    # should really be published
    if ($mode eq 'publish' and not $ENV{KRANG_TEST}) {
        return () unless $self->_do_publish_story($story);
    }

    my $maintain_versions = (($mode eq 'publish') && $args{maintain_versions}) ? 1 : 0;

    my @publish_list = $self->_build_asset_list(
        object            => $story,
        version_check     => $version_check,
        maintain_versions => $maintain_versions,
        initial_assets    => 1
    );

    #     unless ($keep_list) {
    #         $self->_clear_asset_lists();
    #     }

    return \@publish_list;

}

=item C<< $publisher->_process_assets(%args) >>

Called by publish_story(). Method takes in a list of assets to publish in publish_list, 
it than proceeds to write the assets to disk.

Arguments:

=over

=item * C<publish_list>

Array reference of assets to publish.

=item * C<skip_callback>

The optional parameter C<skip_callback> is a pointer to a subroutine
which is called whenever an object is skipped during the publish
process, for whatever reason.  It takes four named parameters:

=item * C<callback>

The optional parameter C<callback> will point to a subroutine which is
called when each object is published to the preview location.  It
recieves three named parameters:

=item * C<remember_asset_list>

Boolean if set to true will not call clear asset lists in _clear_asset_lists()

=item * C<user_id>

Needed to make sure the object to published isn't checked out by another user

=back

=cut

sub _process_assets {
    my ($self, %args) = @_;

    my $total   = @{$args{publish_list}};
    my $counter = 0;

    foreach my $object (@{$args{publish_list}}) {
        if ($object->isa('Krang::Story')) {
            if ($object->checked_out) {
                if ($args{user_id} != $object->checked_out_by) {
                    debug(__PACKAGE__ . ": skipping checked out story id=" . $object->story_id);
                    $args{skip_callback}->(object => $object, error => 'checked_out')
                      if $args{skip_callback};
                    next;
                }
            }

            eval {
                my @paths = $self->_build_story_all_categories(story => $object);

                # fix up publish locations
                $self->_rectify_publish_locations(
                    object  => $object,
                    paths   => \@paths,
                    preview => 0
                );

                # mark as published.
                $object->mark_as_published();

                # don't make callbacks on media, that's handled in publish_media().
                $args{callback}->(
                    object  => $object,
                    total   => $total,
                    counter => $counter++
                ) if $args{callback};

            };

            if (my $err = $@) {
                if ($args{skip_callback}) {

                    # call skip_callback, hopefully with a real error
                    # object
                    $args{skip_callback}->(object => $object, error => $err);
                } else {

                    # the skip_callback is not used by the CGIs,
                    # re-propegate the error so the UI can handle it.
                    die($err);
                }
            }

            # clear the publish context to not dirty things for the
            # next pass.
            $self->clear_publish_context();

        } elsif ($object->isa('Krang::Media')) {

            # publish_media() will mark the media object as published.
            $self->publish_media(
                media               => $object,
                callback            => $args{callback},
                skip_callback       => $args{skip_callback},
                remember_asset_list => $args{remember_asset_list}
            );
        }
    }
}

=item C<< $publisher->_process_preview_assets(%args) >>

Called by preview_story(). Method takes in a list of assets to publish in publish_list, 
it than proceeds to write the assets to the preview_path.  Decoupling of asset list from publishing of assets, permits an more natural entry point for a subclass ( to be written at a later time) to provide parallel publishing behavior.

Arguments:

=over

=item * C<publish_list>

array reference of assets to publish to the preview location.

=item * C<callback>

The optional parameter C<callback> will point to a subroutine which is
called when each object is published to the preview location.  It
recieves three named parameters:

=item * C<story>

Initial story object to preview.

=item * C<unsaved>

defaults to 0.  If C<unsaved> is true,
L<Krang::Story>->preview_version will be set to -1.  What this does
is force a republish of the story object to the preview path the next
time the object comes up as a related object to a story being
previewed.

As part of the publish process, all media and stories linked to by
C<$story> will be examined.  If the current version of each object has
not been published to preview, it will be.  If the object has been
previewed previously, it will be skipped.

=back

=cut

sub _process_preview_assets {
    my ($self, %args) = @_;

    my $total   = @{$args{publish_list}};
    my $counter = 0;

    foreach my $object (@{$args{publish_list}}) {

        if ($object->isa('Krang::Story')) {
            my @paths = $self->_build_story_all_categories(story => $object);

            # fix up publish locations
            $self->_rectify_publish_locations(
                object  => $object,
                paths   => \@paths,
                preview => 1
            );

            # make a note on preview status.  Initial story may be in
            # edit mode, the rest are not.
            if ($object->story_id == $args{story}->story_id) {
                $object->mark_as_previewed(unsaved => $args{unsaved});
            } else {
                $object->mark_as_previewed(unsaved => 0);
            }

            # clear context to not sully the next story.
            $self->clear_publish_context;

        } elsif ($object->isa('Krang::Media')) {
            debug('Publisher.pm: Previewing media_id=' . $object->media_id());
            $self->preview_media(media => $object);
        }

        $args{callback}->(
            object  => $object,
            total   => $total,
            counter => $counter++
        ) if $args{callback};

    }
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

    my $template = $args{template} || croak __PACKAGE__ . ": Missing argument 'template'!\n";

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

    my $template = $args{template} || croak __PACKAGE__ . ": Missing argument 'template'!\n";

    my $category = $template->category();

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

Given the current category, returns the list of directories that may
contain a template.  The first element in the returning array contains
the directory of the current category, the last element contains the
directory of the root category (parent of all categories in the site).

Arguments:

=over

=item * C<category>

An optional argument - if not supplied, the current L<Krang::Category>
category in the publish run is used (usually the best choice).

=back

A note on preview: In preview mode, this method will check to see if
the user has a testing-template temporary directory (created if the
user has templates checked out & flagged for testing).  If so, the
testing-template temporary directory paths will be interspersed with
the deployed-template dirs (in the order of TEST/PROD/TEST/PROD).

=cut

sub template_search_path {

    my $self    = shift;
    my %args    = @_;
    my @subdirs = ();
    my @paths   = ();
    my $category;
    my $preview_root;

    my $user_id = $ENV{REMOTE_USER};

    # Root dir for this instance.
    my $root = catdir(KrangRoot, 'data', 'templates', pkg('Conf')->instance());

    if (exists($args{category})) {
        if (!defined($args{category})) {

            # if category arg is not defined, return root dir for instance.
            # (but check for template testing)
            if ($self->{is_preview}
                && exists($self->{testing_template_path}{$user_id}))
            {
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
        if ($self->{is_preview}
            && exists($self->{testing_template_path}{$user_id}))
        {
            push @paths, catfile($self->{testing_template_path}{$user_id}, @subdirs);
        }

        push @paths, catfile($root, @subdirs);
        pop @subdirs;
    }

    # add root (possibly preview too) dir as well.
    if ($self->{is_preview}
        && exists($self->{testing_template_path}{$user_id}))
    {
        push @paths, $self->{testing_template_path}{$user_id};
    }

    push @paths, $root;

    return @paths;

}

=item C<< $txt = $publisher->page_break() >>

Returns the tag used internally to mark the break between pages in a
story.  When a multi-page story is assembled by the
Krang::ElementClass element tree, it consists of a scaler containing
these break tags.  The preview/publish process will split the scaler
along those tags to create the individual pages of the story.

No exceptions to throw.

=cut

sub page_break {

    return PAGE_BREAK;

}

=item C<< $txt = $publisher->content() >>

Returns the tag used internally to mark the break between the top and
bottom sections of a category page.  Once broken, the individual pages
of a story will be placed in between the two halves, and the full HTML
page will be assembled.

No exceptions to throw.

=cut

sub content {

    return CONTENT;

}

=item C<< $publisher->additional_content_block(filename => $filename, content => $html, use_category => 1); >>

C<additional_content_block> creates an entry in the publisher that
will be re-visited once the entire story content has been constructed.
During the final output of the story, the content C<$html> will be
written out separately to C<$filename>.

C<content> and C<filename> arguments are required.

C<use_category> is a boolean flag that tells Krang::Publisher whether
or not to add the current L<Krang::Category> header/footer to the
final output, as it will for the regular published output.  Defaults
to true.

C<category_tmpl_args> is an optional hashref of keys/values to add
to the $fill_template_args hashref passed to category's fill_template()
method (which by default includes a single key/value pair, additional_content =>
$filename). this of course has no effect if use_category is set to 0.

C<mode> is an optional parameter which will set the permissions
of the file which is published.  The mode should be specified in
octal (NOT a string).  If not specified, the mode of the published
file will be based on the umask.

An optional C<post_process> code ref may be supplied that will receive
the created content as a scalarref after the optional category template
has been applied.

If you want to write binary data (e.g. images), you B<must> specify
the 'binary' argument.

B<WARNING:> C<additional_content_block()> can be called as many times
as desired, however it does not perform any sanity checks on
C<filename> - if your output contains multiple blocks of additional
content with identical filenames, they will overwrite each other, and
only the last one will remain.

=cut

sub additional_content_block {

    my $self = shift;
    my %args = @_;

    my %block;

    $block{content}  = $args{content};
    $block{filename} = $args{filename};
    $block{binary}   = $args{binary};
    croak __PACKAGE__ . ": missing required argument 'content'"  unless defined $block{content};
    croak __PACKAGE__ . ": missing required argument 'filename'" unless length $block{filename};
    $block{use_category} = exists($args{use_category}) ? $args{use_category} : 1;
    $block{mode}         = exists($args{mode})         ? $args{mode}         : undef;
    croak __PACKAGE__ . ": post_process is not a code block"
      if $args{post_process} && !ref $args{post_process} eq 'CODE';
    $block{post_process}       = $args{post_process};
    $block{category_tmpl_args} = $args{category_tmpl_args};

    push @{$self->{additional_content}}, \%block;

}

=item C<< %vars = $publisher->publish_context(%set_params) >>

C<publish_context()> provides a way to set and retrieve parameters in
the L<Krang::Publisher> object during the publish process for a single
story.

C<publish_context()> takes a hash of parameters for storage, and will
return a hash of all stored parameters if called without arguments.
Note that saving the same key-value pair multiple times will result in
only the last variant being stored.

  # store 'foo => bar'
  $publisher->publish_context(foo => 'bar');

  # $vars{foo} is 'bar'
  my %vars = $publisher->publish_context();

  # foo is now 'baz'
  $publisher->publish_context(foo => 'baz');


Note - the internal hash used by C<publish_context()> is cleared after
every story is published - the variables stored here are not
persistant across stories.

=cut

sub publish_context {

    my $self = shift;
    $self->{publish_context} ||= {};

    # check to see if there are params.
    if (@_) {
        my %args = @_;

        foreach my $key (keys %args) {
            $self->{publish_context}{$key} = $args{$key};
        }

        return;
    }

    return $self->{publish_context}
      ? %{$self->{publish_context}}
      : ();
}

=item C<< $publisher->clear_publish_context() >>

Working in conjunction with C<publish_context()> above, clear the
internal hash.

Nothing is returned.

=cut

sub clear_publish_context {

    my $self = shift;

    delete $self->{publish_context};

    $self->{publish_context} = {};

}

=item C<< $filename = $publisher->story_filename(page => $page_num); >>

Returns the filename (B<NOT> the path + filename, just the filename)
of the current story being published, given the page number.

Arguments:

=over

=item * C<page>

The page number of the story.  Defaults to 0.

=item * C<story>

Optional.  Defaults to L<story()>.  Use it if you want a filename for
something other than what is currently being published.

=back

=cut

sub story_filename {

    my $self = shift;
    my %args = @_;

    my $page  = $args{page}  || 0;
    my $story = $args{story} || $self->story;

    my $element = $story->element();

    if ($page == 0) { $page = ''; }

    return $element->class()->filename() . $page . $element->class()->extension();

}

=item C<< $bool = $publisher->test_publish_status(object => $story, mode => 'publish') >>

Checks the current version of the object against its' stored
C<preview_version> or C<published_version>.  If the versions are not
identical, it will return true, indicating that it should be
published.

If the versions are identical, it will perform an additional check for
L<Krang::Story> objects, checking
L<Krang::ElementClass::TopLevel>->C<force_republish>.

Will return 0 (false) if it determines that there is no rule
indicating the asset should be published.

Arguments:

=over

=item * C<object>

The L<Krang::Story> or L<Krang::Media> object to be published.

=item * C<mode>

Either 'preview' or 'publish'.  If this is not set, it will check
L<is_preview()> and L<is_publish()> for an indication of mode.  If
those are not set either, it will croak with an error.

=back

=cut

sub test_publish_status {
    my ($self, %args) = @_;

    my $object = $args{object} || croak "Missing required argument 'object'";
    my $mode = $args{mode};

    my $publish_yes = 0;

    if ($mode) {
        if    ($mode eq 'preview') { $self->_set_preview_mode(); }
        elsif ($mode eq 'publish') { $self->_set_publish_mode(); }
        else                       { croak __PACKAGE__ . ": unknown output mode '$mode'\n"; }
    } else {
        if    ($self->is_preview()) { $mode = 'preview'; }
        elsif ($self->is_publish()) { $mode = 'publish'; }
        else {
            croak "Publish mode unknown.  Set the 'mode' argument'";
        }
    }

    # check versioning.
    if ($mode eq 'preview') {
        $publish_yes = 1 unless ($object->preview_version == $object->version);
    } else {
        $publish_yes = 1 unless ($object->published_version == $object->version);
    }

    return $publish_yes if $publish_yes;

    # otherwise, check on the filesystem for missing files.
    $publish_yes = $self->_check_object_missing(object => $object);
    return $publish_yes if $publish_yes;

    # for stories, can check force_republish.
    if ($object->isa('Krang::Story')) {
        $publish_yes = $object->element->class->force_republish();
    }

    return $publish_yes;

}

=item C<< $url = $publisher->url_for(object => $story) >>

=item C<< $url = $publisher->url_for(object => $media) >>

=item C<< $url = $publisher->url_for(object => $category) >>

=item C<< $url = $publisher->url_for(object => $site) >>

=item C<< $url = $publisher->url_for(object => $object) >>

Returns the object's URL according to the publishing context.
Object may be a L<Krang::Story>, L<Krang::Media>,
L<Krang::Category>, L<Krang::Site> or any other object having both methods
url() and preview_url() .

Returns the empty string if $object is not an object of any type.

Croaks if $object does not have both methods url() and preview_url() .

=cut

sub url_for {
    my ($self, %arg) = @_;

    my $object = $arg{object};

    return '' unless ref($object);

    # duck typing object check
    for my $method (qw(url preview_url)) {
        unless ($object->can($method)) {
            croak(__PACKAGE__ . ': ' . ref($object) . " misses required method '$method'.");
        }
    }

    # build URL
    if ($self->is_publish) {
        return 'http://' . $object->url;
    } elsif ($self->is_preview) {
        my $scheme = PreviewSSL ? 'https' : 'http';
        return "$scheme://" . $object->preview_url();
    } else {
        croak(__PACKAGE__ . ': Not in publish nor preview mode. Cannot return proper URL.');
    }
}

=back

=head1 TODO

Nothing at the moment.

=head1 SEE ALSO

L<Krang::ElementClass>, L<Krang::Category>, L<Krang::Media>

=cut

# $self->_rectify_publish_locations(object => $object, paths=>[], preview => 1)
#
# remove any dangling files previously published for this object and
# update the publish location data in the DB

sub _rectify_publish_locations {
    my $self    = shift;
    my %arg     = @_;
    my $object  = $arg{object};
    my $paths   = $arg{paths} || [];
    my $preview = $arg{preview};
    my $type    = $object->isa('Krang::Story') ? 'story' : 'media';
    my $id      = $type eq 'story' ? $object->story_id : $object->media_id;
    my $dbh     = dbh;

    # get old location list
    my $old_paths = $dbh->selectcol_arrayref(
        "SELECT path FROM publish_${type}_location 
        WHERE ${type}_id = ? AND preview = ?", undef, $id, $preview
    );

    # build hash of current paths
    my %cur = map { ($_, 1) } @$paths;

    # delete any files that aren't part of the current set
    foreach my $old (@$old_paths) {
        next if $cur{$old};
        next unless -f $old;

        # make sure this path isn't claimed by another object
        my ($claimed) = $dbh->selectrow_array(
            "SELECT 1 FROM publish_${type}_location "
              . "WHERE path = ? AND preview = ? "
              . "AND ${type}_id != ?",
            undef, $old, $preview, $id
        );
        next if $claimed;

        unlink($old)
          or croak("Unable to delete extinct publish result '$old'.");
    }

    # write new paths to publish location table if we have an id (it
    # was saved)
    if ($id) {
        $dbh->do(
            "DELETE FROM publish_${type}_location 
                  WHERE ${type}_id = ? AND preview = ?", undef, $id, $preview
        );
        $dbh->do(
            "INSERT INTO publish_${type}_location 
                  (${type}_id,preview,path) VALUES " . join(',', ('(?,?,?)') x @$paths),
            undef, map { ($id, $preview, $_) } @$paths
        ) if @$paths;
    }
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

    my $user_id = $ENV{REMOTE_USER}
      || croak __PACKAGE__ . ": 'REMOTE_USER' environment variable is not set!\n";

    # find any templates checked out by this user that are marked for testing.
    my @templates = pkg('Template')->find(testing => 1, checked_out_by => $user_id);

    # if there are no templates, there's nothing left to do here.
    return unless (@templates);

    # there are templates - create a tempdir & deploy these bad boys.
    $path = tempdir(DIR => catdir(KrangRoot, 'tmp'));
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

    my $user_id = $ENV{REMOTE_USER}
      || croak __PACKAGE__ . ": 'REMOTE_USER' environment variable is not set!\n";

    # there's no work if there's no dir.
    return unless exists($self->{testing_template_path}{$user_id});

    eval { rmtree($self->{testing_template_path}{$user_id}); };

    if ($@) {
        croak __PACKAGE__
          . ": error removing temporary dir '$self->{testing_template_path}{$user_id}': $@";
    }

    delete $self->{testing_template_path}{$user_id};

    return;
}

#
# @paths = _build_story_all_categories(story => $story);
#
# Handles the process for publishing a story out over all its various categories.
#
# Returns a list of file-system paths where the story was written

sub _build_story_all_categories {

    my $self = shift;
    my %args = @_;

    my $story = $args{story};

    my @categories = $story->categories();

    # Categories & Story URLs are in identical order.  Move in lockstep w/ both of them.
    my @paths;
    foreach (my $i = 0 ; $i <= $#categories ; $i++) {
        push @paths,
          $self->_build_story_single_category(
            story    => $story,
            category => $categories[$i]
          );
    }

    # log history
    if ($self->{is_publish}) {
        add_history(object => $story, action => 'publish');
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
    my @pages;

    my $additional_content;
    my ($cat_header, $cat_footer);

    my $story    = $args{story}    || croak __PACKAGE__ . "missing argument 'story'";
    my $category = $args{category} || croak __PACKAGE__ . "missing argument 'category'";

    my $output_path = $self->_determine_output_path(object => $story, category => $category);

    # set internal values for accessor methods to call.
    $self->{category} = $category;
    $self->{story}    = $story;

    # get root element for the story & category.
    my $story_element    = $story->element();
    my $category_element = $category->element();

    # get story output
    my $article_output = $story_element->publish(publisher => $self);

    # maybe add preview editor overlay
    my $div = EnablePreviewEditor && $self->is_preview
      ? pkg('ElementClass')->_get_preview_editor_element_overlays(child => $story_element, publisher => $self)
      : '';

    # break the story into pages
    my @article_pages = map { $div . $_ } split(/${\PAGE_BREAK}/, $article_output);

    # if nothing returned, we have a problem.  Throw an error.
    if ($#article_pages < 0) {
        my $url = $self->is_preview() ? $category->preview_url : $category->url;

        Krang::Publisher::ZeroSizeOutput->throw(
            message  => sprintf("Story %i output for %s is zero-length", $story->story_id, $url),
            story_id => $story->story_id,
            category_url => $url,
            story_class  => $story->class->name
        );
    }

    # chuck the last page if it's only whitespace.
    if ($#article_pages > 0) {
        pop @article_pages if ($article_pages[$#article_pages] =~ /^\s*$/);
    }

    # check to see if category output is needed
    if ($story_element->use_category_templates()) {

        # category pages must be published once for each story page.
        if ($story_element->class->publish_category_per_page()) {
            my $i = 0;
            foreach my $p (@article_pages) {
                my %tmpl_args = (
                    page_index      => $i,
                    last_page_index => $#article_pages
                );
                my ($head, $foot) =
                  $self->_cat_content($category_element, fill_template_args => \%tmpl_args);
                my $output = $head . $p . $foot;
                push @pages, $output;

                # cat_header and cat_footer need to be set w/ first
                # page tmpl for additional content needs.
                unless ($i) {
                    $cat_header = $head;
                    $cat_footer = $foot;
                }
                $i++;
            }
        } else {
            ($cat_header, $cat_footer) = $self->_cat_content($category_element);

            # assemble the components.
            foreach (@article_pages) {
                my $page = $cat_header . $_ . $cat_footer;
                push @pages, $page;
            }
        }
    } else {

        # no category templates being used.
        @pages = @article_pages;
    }

    # write additional content to disk
    while (my $block = shift @{$self->{additional_content}}) {
        my $content = $block->{content};
        if ($block->{use_category}) {
            my $tmpl_args = $block->{category_tmpl_args} || {};
            $tmpl_args->{additional_content} = $block->{filename};
            ($cat_header, $cat_footer) =
              $self->_cat_content($category_element, fill_template_args => $tmpl_args)
              unless (($cat_header or $cat_footer)
                and not $story_element->class->publish_category_per_page());
            $content = $cat_header . $content . $cat_footer;
        }

        if ($block->{post_process}) {
            $block->{post_process}->(\$content);
        }

        my $output_filename = $self->_write_page(
            data     => $content,
            filename => $block->{filename},
            binary   => $block->{binary},
            story_id => $story->story_id,
            path     => $output_path
        );
        push(@paths, $output_filename);

        # set mode if available
        if (my $mode = $block->{mode}) {
            chmod($mode, $output_filename)
              or croak("Unable to chmod($mode, $output_filename): $!");
        }

    }

    push @paths, $self->_write_story(story => $story, pages => \@pages, path => $output_path);

    return @paths;
}

# gets header and footer from category publishing
sub _cat_content {
    my ($self, $category_element, %args) = @_;
    my $category_output = $category_element->publish(
        publisher => $self,
        %args
    );
    return split(/${\CONTENT}/, $category_output, 2);
}

##################################################
##
## Asset Link Checking
##

#
# @assets = _build_asset_list(object => \@story, version_check => 1, initial_assets => 1);
#
# Recursively builds the list of assets to be published, called by
# asset_list().
#
# story can be either a Krang::Story or Krang::Media object, or a
# listref of Story/Media objects.
#
# version_check will check preview/published_version if true.
# Defaults true.
#
# initial_assets will skip that check when true - used for the first
# call from asset_list().  Defaults false.
#
# maintain_versions defaults to 0. If true, we will build a list of the last-published
# version of each asset (if any) rather than the latest version.
#
# Returns a list of Krang::Story and Krang::Media objects.
#
sub _build_asset_list {
    my ($self, %args) = @_;

    my $object            = $args{object};
    my $version_check     = (exists($args{version_check})) ? $args{version_check} : 1;
    my $initial_assets    = (exists($args{initial_assets})) ? $args{initial_assets} : 0;
    my $maintain_versions = (exists($args{maintain_versions})) ? $args{maintain_versions} : 0;

    my @asset_list;
    my @check_list;

    my @objects = (ref $object eq 'ARRAY') ? @$object : ($object);
    foreach my $o (@objects) {

        # don't publish (linked) objects that are retired or trashed
        next if $self->is_publish() && $o->can('wont_publish') && $o->wont_publish();

        # handle 'maintain_versions' mode
        if ($maintain_versions) {
            unless ($o->checked_out && ($o->checked_out_by != $ENV{REMOTE_USER})) {
                my $v = $o->published_version;
                next unless $v;
                if ($v != $o->version) {
                    if ($o->isa('Krang::Story')) {
                        ($o) = pkg('Story')->find(story_id => $o->story_id, version => $v);
                    } else {
                        ($o) = pkg('Media')->find(media_id => $o->media_id, version => $v);
                    }
                }
            }
        }
        my ($publish_ok, $check_links) = $self->_check_asset_status(
            object         => $o,
            version_check  => $version_check,
            initial_assets => $initial_assets
        );

        push @asset_list, $o if ($publish_ok);
        if ($check_links) {
            my $check_stories = !($self->is_preview && IgnorePreviewRelatedStoryAssets);
            my $check_media   = !($self->is_preview && IgnorePreviewRelatedMediaAssets);
            push @check_list, $o->linked_stories(publisher => $self) if $check_stories;
            push @check_list, $o->linked_media if $check_media;
        }
    }

    # if there are objects to be checked, check 'em.
    push @asset_list,
      $self->_build_asset_list(
        object            => \@check_list,
        version_check     => $version_check,
        maintain_versions => $maintain_versions,
        initial_assets    => 0,
      ) if (@check_list);

    return @asset_list;
}

#
# ($publish_ok, $check_links) = _check_object_status(object => $object,
#                                                    initial_assets => 1
#                                                    version_check  => 1);
#
# checks the Krang::Story or Krang::Media object to see if it should
# be added to the publish list, and whether or not it needs to be
# checked for related assets.
#
# object - a Krang::Story or Krang::Media object
#
#

sub _check_asset_status {

    my ($self, %args) = @_;

    my $object = $args{object} || croak __PACKAGE__ . ": missing argument 'object'";
    my $version_check  = (exists($args{version_check}))  ? $args{version_check}  : 1;
    my $initial_assets = (exists($args{initial_assets})) ? $args{initial_assets} : 0;

    my $publish_ok  = 0;
    my $check_links = 0;

    my $instance = pkg('Conf')->instance();

    if ($self->_mark_asset(object => $object)) {
        if ($initial_assets || !$version_check) {
            $publish_ok = 1;
        } elsif ($self->test_publish_status(%args)) {
            $publish_ok = 1;
        }
    }

    if ($self->_mark_asset_links(object => $object)) {
        $check_links = 1;
    }

    return ($publish_ok, $check_links);
}

#
# $bool = _mark_asset(object => $object)
#
# Checks to see if the object exists in the asset list.
#
# If it does not exist, the object is added to the asset list, and 1 is returned.
# If it does exist, 0 is returned.
#

sub _mark_asset {

    my ($self, %args) = @_;

    my $object = $args{object} || croak __PACKAGE__ . ": missing argument 'object'";

    my $instance = pkg('Conf')->instance();

    my $set;
    my $id;

    # make sure the asset list exists - non-destructive init.
    $self->_init_asset_lists();

    if ($object->isa('Krang::Story')) {
        $set = 'story_publish_set';
        $id  = $object->story_id();
    } elsif ($object->isa('Krang::Media')) {
        $set = 'media_publish_set';
        $id  = $object->media_id();
    } else {

        # should never get here.
        croak sprintf("%s->_mark_asset: unknown object type: %s\n", __PACKAGE__, $object->isa);
    }

    if ($self->{asset_list}{$instance}{$set}{$id}) {
        return 0;
    }

    # not seen before.
    $self->{asset_list}{$instance}{$set}{$id} = 1;
    return 1;

}

#
# $bool = _mark_asset_links(object => $object)
#
# Returns 1 if the object has not been checked previously for related links.
# Returns 0 if the object has been checked before.
#
# Returns 0 if the object is not a Krang::Story object (and therefore has no related assets).
#

sub _mark_asset_links {
    my ($self, %args) = @_;

    my $object = $args{object} || croak __PACKAGE__ . ": missing argument 'object'";

    return 0 unless ($object->isa('Krang::Story'));

    # make sure the asset list exists - non-destructive init.
    $self->_init_asset_lists();

    my $instance = pkg('Conf')->instance();
    my $story_id = $object->story_id();

    if ($self->{asset_list}{$instance}{checked_links_set}{$story_id}) {
        return 0;
    }
    $self->{asset_list}{$instance}{checked_links_set}{$story_id} = 1;
    return 1;

}

#
# $bool = _check_object_missing(object => $object);
#
# Checks all possible filesystem locations for an object (e.g. where
# they could get published to), returns false if they all exist, true
# if any of them cannot be found on the filesystem
#
# object is a Krang::Story or Krang::Media object
#

sub _check_object_missing {

    my ($self, %args) = @_;

    my $object = $args{object} || croak __PACKAGE__ . ": missing argument 'object'";

    my $bool = 0;

    if ($object->isa('Krang::Story')) {

        # check all categories
        foreach my $cat ($object->categories) {
            my $path = $self->_determine_output_path(object => $object, category => $cat);
            my $filename = $self->story_filename(story => $object);
            my $output_filename = catfile($path, $filename);
            unless (-e $output_filename) {

                # if any are missing, true.
                $bool = 1;
                last;
            }
        }
    } else {
        my $path = $self->_determine_output_path(object => $object);
        $bool = 1 unless (-e $path);
    }

    return $bool;
}

#
# _init_asset_lists()
#
# Set up the internally-maintained lists of asset IDs,
# these lists are used by asset_list to determine which assets are
# going to get published.
#

sub _init_asset_lists {

    my $self = shift;

    my $instance = pkg('Conf')->instance();

    foreach (qw(story_publish_set media_publish_set checked_links_set)) {
        $self->{asset_list}{$instance}{$_} = {} unless (exists($self->{asset_list}{$instance}{$_}));
    }
}

#
# _clear_asset_lists()
#
# Nukes all content in the asset lists.
#

sub _clear_asset_lists {

    my $self = shift;

    my $instance = pkg('Conf')->instance();

    foreach (keys %{$self->{asset_list}{$instance}}) {
        delete $self->{asset_list}{$instance}{$_};
    }

    delete $self->{asset_list};
}

############################################################
#
# ADDITIONAL CONTENT METHODS
#

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
    eval { mkpath($dir_path, 0, 0755); };
    if ($@) {
        Krang::Publisher::FileWriteError->throw(
            message      => "Could not create output directory: $@",
            destination  => $dir_path,
            system_error => $@
        );
    }

    # copy file out to the production path
    unless (copy($internal_path, $output_path)) {
        Krang::Publisher::FileWriteError->throw(
            message      => "Could not copy media file from " . $internal_path . ": $!",
            media_id     => $media->media_id(),
            source       => $internal_path,
            destination  => $output_path,
            system_error => $!
        );
    }

    # fix up output location
    $self->_rectify_publish_locations(
        object  => $media,
        paths   => [$output_path],
        preview => $self->{is_preview}
    );

    # if media element has a publish() method, call it
    # (we do this in _write_media() since it's called by
    # both publish_media() and preview_media())
    if ($media->element->class->can('publish')) {
        $media->element->class->publish(
            publisher => $self,
            media     => $media,
            element   => $media->element
        );
    }

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
    my $class = $story->element->class;
    my $mode_fn = $class->can('file_mode') || sub { };

    my @created_files;

    for (my $page_num = 0 ; $page_num < @$pages ; $page_num++) {

        my $filename = $self->story_filename(story => $story, page => $page_num);

        my $output_filename = $self->_write_page(
            path     => $output_path,
            filename => $filename,
            story_id => $story->story_id,
            data     => $pages->[$page_num]
        );

        # set mode if available
        if (my $mode = $mode_fn->($class, $output_filename)) {
            chmod($mode, $output_filename)
              or croak("Unable to chmod($mode, $output_filename): $!");
        }

        push(@created_files, $output_filename);
    }

    return @created_files;

}

#
# $output_filename = _write_page(path => $path, filename => $filename, data => $content, story_id => $id);
#
# To write binary data:
#
# $output_filename = _write_page(path => $path, filename => $filename, data => $content, story_id => $id, binary => 0);
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
        croak __PACKAGE__ . ": missing parameter '$_'.\n" unless defined($args{$_});
    }

    eval { mkpath($args{path}, 0, 0755); };
    if ($@) {
        Krang::Publisher::FileWriteError->throw(
            message      => "Could not create directory '$args{path}': $@",
            destination  => $args{path},
            system_error => $@
        );
    }

    my $output_filename = catfile($args{path}, $args{filename});

    my $fh = pkg('IO')->io_file(">$output_filename", 'binary' => $args{binary})
      or Krang::Publisher::FileWriteError->throw(
        message      => "Cannot output story to $output_filename: $!",
        story_id     => $args{story_id},
        destination  => $output_filename,
        system_error => $!
      );
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

    my $template = $args{template};
    my $id       = $template->template_id();

    my $category = $template->category();

    my @tmpl_dirs = $self->template_search_path(category => $category);

    my $path = $tmpl_dirs[0];

    eval { mkpath($path, 0, 0755); };
    if ($@) {
        Krang::Publisher::FileWriteError->throw(
            message      => "Could not create publish directory: $@",
            destination  => $path,
            system_error => $@
        );
    }

    my $file = catfile($path, $template->filename());

    # write out file
    my $fh = pkg('IO')->io_file(">$file")
      or Krang::Publisher::FileWriteError->throw(
        message      => "Cannot deploy template: $!",
        template_id  => $id,
        destination  => $file,
        system_error => $!
      );
    $fh->print($template->{content});
    $fh->close();

    return $file;

}

#
# $path = $self->_determine_output_path(object => $object, category => $category);
#
# For Krang::Story objects, returns the directory under which the
# story will be written on the filesystem for a given category.
#
# For Krang::Media objects, returns the full path to file.
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
        if ($object->isa('Krang::Story')) {
            my $category = $args{category} || croak __PACKAGE__ . ": missing argument 'category'";
            $output_path = $object->preview_path(category => $category);
        } else {
            $output_path = $object->preview_path();
        }
    } else {
        croak __PACKAGE__ . ": Cannot determine preview/publish mode";
    }

    return $output_path;
}

# Returns true if the story must be published
sub _do_publish_story {
    my ($self, $story) = @_;

    # a couple of flags
    my ($do_publish, $has_category_link, $conditional_publishing) = (0,0,0);

    # check story for CategoryLink elements
    foreach_element {
        return unless $_;
        my $element = $_;

        # get CategoryLink element
        if ($element->class->isa('Krang::ElementClass::CategoryLink')) {

            # Remember that we have at least one CategoryLink
            $has_category_link++;
            my $category = $element->data;

            # no category: return immediately
            return unless $category && ref($category) && $category->isa('Krang::Category');

            # check if stories or media IN or BELOW category have been modified
            my $class = $element->class;
            for my $asset (qw(story media)) {
                my %find_params = ();
                if ($class->{"publish_if_modified_".$asset."_in_cat"}) {
                    $find_params{category_id} = $category->category_id;
                }
                if ($class->{"publish_if_modified_".$asset."_below_cat"}) {
                    $find_params{below_category_id} = $category->category_id;
                }

                if (keys %find_params) {

                    # Remember that we are in 'conditional publishing mode'
                    $conditional_publishing++;

                    for my $asset (pkg(ucfirst($asset))->find(%find_params)) {
                        if ($asset->is_modified()) {
                            # at least one asset is modified
                            $do_publish++;
                            return 1;
                        }
                    }
                }
            }
        }
    } $story->element;

    # no categorylink: publish the story
    return 1 unless $has_category_link;

    # we are in 'conditional publishing mode' and at least one asset
    # has been modified since its last publishing
    return 1 if $do_publish;

    # we have a categorylink without being in 'conditional publishing
    # mode' which can mean either that none of the 'conditional
    # publishing flags' have been set or that there is a categorylink
    # without a category being set.
    return 1 unless $conditional_publishing;

    # we are in 'conditional publishing mode' and none of the
    # category's assets have been modified
    return;
}

############################################################
#
# MODES -
#
# The internal hash keys is_preview and is_publish are checked in a lot of places
# quick subroutines to cut down on issues.
#

sub _set_preview_mode {

    my $self = shift;

    $self->{is_preview} = 1;
    $self->{is_publish} = 0;

}

sub _set_publish_mode {

    my $self = shift;

    $self->{is_preview} = 0;
    $self->{is_publish} = 1;

}

my $EBN = <<EOEBN;

This is a test of the emergency broadcast network.

Please stand by and await further instructions.

EOEBN
