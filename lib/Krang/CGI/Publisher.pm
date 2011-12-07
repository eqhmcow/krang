package Krang::CGI::Publisher;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::CGI::Publisher - the publisher frontend

=head1 SYNOPSIS

None.

=head1 DESCRIPTION

This application provides a frontend to Krang::Publisher 

=head1 INTERFACE

=head2 Run-Modes

=over 4

=cut

use Krang::ClassLoader 'Session';
use Krang::ClassLoader 'Publisher';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'User';
use Krang::ClassLoader 'Cache';
use Krang::ClassLoader 'MyPref';
use Krang::ClassLoader Conf         => qw(PreviewSSL Charset EnablePreviewEditor);
use Krang::ClassLoader Log          => qw(debug info critical assert ASSERT);
use Krang::ClassLoader Widget       => qw(format_url datetime_chooser decode_datetime);
use Krang::ClassLoader Message      => qw(add_message add_alert get_alerts clear_alerts);
use Krang::ClassLoader Localization => qw(localize);

use Time::Piece;
use JSON::Any;
use Carp qw(croak);
use URI::Escape qw(uri_escape);

use Krang::ClassLoader base => 'CGI';

sub setup {
    my $self = shift;
    $self->start_mode('preview_story');
    $self->mode_param('rm');
    $self->tmpl_path('Publisher/');
    $self->run_modes(
        [
            qw(
              preview_story
              preview_media
              publish_story
              publish_story_list
              publish_assets
              publish_media
              preview_editor
              )
        ]
    );

}

=item publish_story

Presents a list of story and media objects to be published.  Allows
the user to schedule a publish date.

Requires story_id parameter with the ID of the story to be published.

=cut

sub publish_story {
    my $self  = shift;
    my $query = $self->query;

    my $story_id = $query->param('story_id');
    croak("Missing required story_id parameter") unless $story_id;

    $query->delete('story_id');

    $story_id =~ s/^story_(\d+)$/$1/go;

    my ($story) = pkg('Story')->find(story_id => $story_id);

    croak("Unable to load story for story_id '$story_id'")
      unless $story;

    my $t = $self->load_tmpl(
        'publish_list.tmpl',
        associate         => $query,
        loop_context_vars => 1,
        die_on_bad_params => 0
    );

    my ($stories, $media, $checked_out) = $self->_build_asset_list([$story]);

    add_message('checked_out_assets') if ($checked_out);

    $t->param(stories => $stories, media => $media);
    $t->param(asset_id_list => [{id => "story_$story_id"}]);

    # add date chooser
    $t->param(
        publish_date_chooser => datetime_chooser(
            name     => 'publish_date',
            query    => $query,
            onchange => "this.form['publish_now'][1].checked = true", # when a date is selected, auto-select "Schedule For..." radio button
        )
    );

    return $t->output();
}

=item publish_story_list

Presents a list of story and media objects to be published.  Allows
the user to schedule a publish date.

Requires story_id_list parameter with the IDs of the story to be published.

=cut

sub publish_story_list {
    my $self  = shift;
    my $query = $self->query;

    my (@story_list, @media_list, @story_id_list, @media_id_list, @template_id_list);

    my @asset_id_list = $query->param('krang_pager_rows_checked');

    my $t = $self->load_tmpl(
        'publish_list.tmpl',
        associate         => $query,
        loop_context_vars => 1,
        die_on_bad_params => 0
    );
    my @id_list;

    foreach my $asset (@asset_id_list) {

        # if only media ids are being passed in from media find
        if ($query->param('asset_type')
            && ($query->param('asset_type') eq 'media'))
        {
            push @id_list, {id => 'media_' . $asset};
            push(@media_id_list, $asset);
            next;
        }

        # if it's just a number then we're publishing stories
        if ($asset =~ /^(\d+)$/) {
            push @id_list, {id => $asset};    # save for actual publishing
            push(@story_id_list, $1);
        } elsif ($asset =~ /^(\w+)_(\d+)$/) {
            my $type = $1;
            if ($type eq 'story') {
                push(@story_id_list, $2);
                push @id_list, {id => $asset};    # save for actual publishing
            } elsif ($type eq 'media') {
                push(@media_id_list, $2);
                push @id_list, {id => $asset};    # save for actual publishing
            } elsif ($type eq 'template') {

                # templates don't need to be saved for publishing since we
                # deploy them in down in the next section
                push(@template_id_list, $2);
            } else {
                croak __PACKAGE__ . ": what to do with asset type = '$type'??";
            }
        } else {
            croak __PACKAGE__ . ": what to do with asset = '$asset'??";
        }
    }

    # take care of templates first, they don't go to the next screen
    if (@template_id_list) {
        my $publisher = pkg('Publisher')->new();
        foreach my $template_id (@template_id_list) {
            my ($template) = pkg('Template')->find(template_id => $template_id);
            add_message('deployed', id => $template_id);
            $publisher->deploy_template(template => $template);
            $template->checkin;
        }
    }

    # if there are no stories and media, return to workspace directly
    unless (@story_id_list or @media_id_list) {
        return $self->redirect_to_workspace;
    }

    @story_list = pkg('Story')->find(story_id => \@story_id_list) if @story_id_list;
    @media_list = pkg('Media')->find(media_id => \@media_id_list) if @media_id_list;

    my ($stories, $media, $checked_out) = $self->_build_asset_list(\@story_list, \@media_list);

    add_message('checked_out_assets') if ($checked_out);

    $t->param(
        stories       => $stories,
        media         => $media,
        asset_id_list => \@id_list,
    );

    # add date chooser
    $t->param(
        publish_date_chooser => datetime_chooser(
            name     => 'publish_date',
            query    => $query,
            onchange => "this.form['publish_now'][1].checked = true"
        )
    );
    return $t->output();

}

=item publish_assets

Starts the publish process for a given set of stories stories specified by the CGI parameter 'asset_publish_list'.

B<NOTE>: 'asset_publish_list' does not necessarily contain all items listed when the publish process is initiated - it only lists 

Requires the following parameters: story_ids, publish_now, publish_date_xxx (if publish_now == 0)

If publish_now == 1, start publish, show a status bar then redirect to workspace.

If putlist_now == 0, schedule publish & redirect to workspace.

=cut

sub publish_assets {
    my $self  = shift;
    my $query = $self->query;

    my @asset_id_list = ($query->param('asset_id_list'));
    croak("Missing required asset_id_list parameter") unless @asset_id_list;
    my $publish_now = $query->param('publish_now');

    my @story_id_list;
    my @media_id_list;

    my @story_list;
    my @media_list;

    foreach (@asset_id_list) {
        push(@story_id_list, $1), next if /^(\d+)$/;

        if (/^(\w+)_(\d+)$/) {
            push(@story_id_list, $2), next if $1 eq 'story';
            push(@media_id_list, $2), next if $1 eq 'media';
        }
        croak __PACKAGE__ . ": what to do with asset = '$1'??";
    }

    @story_list = pkg('Story')->find(story_id => \@story_id_list) if @story_id_list;
    @media_list = pkg('Media')->find(media_id => \@media_id_list) if @media_id_list;

    if ($publish_now) {
        $self->_publish_assets_now(\@story_list, \@media_list);
    } else {

        # pass things to the scheduler
        my $date = decode_datetime(name => 'publish_date', query => $query);
        $self->_schedule_assets(\@story_list, \@media_list, $date);

        # return to my workspace
        return $self->redirect_to_workspace;
    }

}

=item publish_media

Publishes a media object immediately.  No scheduling done here.

requires media_id

returns the user to 'My Workspace' when done.

=cut

sub publish_media {
    my $self  = shift;
    my $query = $self->query;

    my $media_id = $query->param('media_id');
    croak("Missing required media_id parameter") unless $media_id;

    $media_id =~ s/^media_(\d+)$/$1/go;
    my ($media) = pkg('Media')->find(media_id => $media_id);

    # run things to the publisher
    my $publisher = pkg('Publisher')->new();
    $publisher->publish_media(media => $media);

    # add a message
    add_message(
        'media_publish',
        media_id => $media_id,
        url      => $media->url,
        version  => $media->version
    );

    # return to my workspace
    return $self->redirect_to_workspace;

}

=item preview_story

Publishes a story to preview and returns a redirect to the resulting
page on the preview story.  Requires a story_id parameter with the ID
for the story to be previewed or a session parameter set to the
session key containing the story to preview.

=cut

sub preview_story {
    my $self      = shift;
    my $query     = $self->query;
    my $story_id  = $query->param('story_id');
    my $edit_uuid = $query->param('edit_uuid');

    # if they didn't give us enough to find the story
    # take them back to the workspace
    unless ($story_id || $edit_uuid) {
        info("Missing required story_id or edit_uuid parameter. Redirecting to workspace.");
        return $self->redirect_to_workspace;
    }

    # this is a no-parse header script
    $self->header_type('none');
    print $query->header(-expires => '-1d');

    my $story;
    my $unsaved = 0;

    if ($story_id) {
        ($story) = pkg('Story')->find(story_id => $story_id);
        croak("Unable to find story '$story_id'") unless $story;
    } else {
        $story = $self->get_session_story_obj($edit_uuid);
        croak("Unable to load story from session for edit_uuid $edit_uuid") unless $story;
        $unsaved = 1;
    }

    # output the progress header
    my $template = $self->load_tmpl('progress.tmpl');
    $template->param(preview => 1);
    my $charset = Charset || '';
    $template->param(charset => $charset);
    $|++;
    print $template->output;

    # start up the cache and setup an eval{} to catch any death
    pkg('Cache')->start();
    my ($url);
    eval {
        my $publisher = pkg('Publisher')->new();
        eval {
            $url = $publisher->preview_story(
                story    => $story,
                callback => \&_progress_callback,
                unsaved  => $unsaved
            );
        };

        if (my $error = $@) {
            # if there is an error, figure out what it is, create the
            # appropriate message and return an error page.
            if (ref $error && $error->isa('Krang::ElementClass::TemplateNotFound')) {
                if ($error->included_file) {
                    add_alert(
                        'missing_template_include',
                        filename      => $error->template_name,
                        included_file => $error->included_file,
                        category_url  => $error->category_url
                    );
                } else {
                    add_alert(
                        'missing_template',
                        filename     => $error->template_name,
                        category_url => $error->category_url
                    );
                }
            } elsif (ref $error && $error->isa('Krang::ElementClass::TemplateParseError')) {
                add_alert(
                    'template_parse_error',
                    element_name  => $error->element_name,
                    template_name => $error->template_name,
                    category_url  => $error->category_url,
                    error_msg     => $error->message
                );
            } elsif (ref $error and $error->isa('Krang::Publisher::FileWriteError')) {
                add_alert('file_write_error', path => $error->destination);

                # pass a more informative message to the log file - ops should know.
                my $err_msg = sprintf("Could not write '%s' to disk.  Error='%s'",
                    $error->destination, $error->message);
                critical($err_msg);

            } elsif (ref $error and $error->isa('Krang::Publisher::ZeroSizeOutput')) {
                add_alert(
                    'zero_size_output',
                    story_id     => $error->story_id,
                    category_url => $error->category_url,
                    story_class  => $error->story_class
                );

            } else {
                critical($error);
                croak($error);
            }

            # put the messages on the screen
            foreach my $msg (get_alerts()) {
                print '<div class="alertp">' . $query->escapeHTML($msg) . "</div>\n";
            }
            clear_alerts();

            # make sure to turn off caching
            pkg('Cache')->stop();
            debug("Cache Stats " . join(' : ', pkg('Cache')->stats()));

            return '';
        }
    };
    my $err = $@;

    # cache off, regardless of $err
    pkg('Cache')->stop();
    debug("Cache Stats " . join(' : ', pkg('Cache')->stats()));

    # die a rightful death
    croak($err) if $err;

    # this should always be true
    assert($url eq $story->preview_url) if $url && ASSERT;

    # dynamic redirect to preview if we've got a url to redirect to
    my $scheme = PreviewSSL ? 'https' : 'http';

    if ($url) {
        # w/o preview editor
        if (pkg('MyPref')->get('use_preview_editor') && !$query->param('exit_preview_editor')) {
            # display the previewed story in a frame within the main window
            my $qstring = "rm=preview_editor&story_preview_url=" . uri_escape("$scheme://$url");

            print qq|
                <script type="text/javascript">
                    setTimeout(
                        function() { Krang.Nav.goto_url("publisher.pl?$qstring") },
                        10
                    )
                </script>
            |;
            return;
        } else {
            # display the previewed story in the main window
            print qq(<script type="text/javascript">Krang.Nav.goto_url('$scheme://$url')</script>);
        }
    }
}

=item preview_editor

Displays the previewed story in a frame within the story preview window.

=cut

sub preview_editor {
    my ($self) = @_;
    my $query  = $self->query;

    my $t = $self->load_tmpl(
        'preview_editor.tmpl',
        die_on_bad_params => 0,
    );

    $t->param(
        story_preview_url => ($query->param('story_preview_url') || ''),
        json => JSON::Any->new->encode({cmsURL => pkg('Conf')->cms_root()}),
    );
    return $t->output;
}

# update the progress bar during preview or publish
sub _progress_callback {
    my %arg = @_;
    my ($object, $counter, $total) = @arg{qw(object counter total)};
    my $string;
    if ($object->isa('Krang::Story')) {
        $string = "Story " . $object->story_id . ": " . $object->url;
    } else {
        $string = "Media " . $object->media_id . ": " . $object->url;
    }
    print qq|
        <script type="text/javascript">Krang.Progress.update($counter, $total, '$string');</script>
    |;
}

=item preview_media

Publishes a media object to preview and returns a redirect to the
resulting URL.  Requires a media_id parameter with the ID for the
media to be previewed, or a parameter called session set to the
session key containing the media object.

=cut

sub preview_media {
    my $self      = shift;
    my $query     = $self->query;
    my $edit_uuid = $query->param('edit_uuid');
    my $media_id  = $query->param('media_id');
    croak("Missing required media_id or edit_uuid parameter.") unless $media_id or $edit_uuid;

    # if this is set, don't redirect to preview server
    my $no_view = $query->param('no_view');

    my $media;
    if($media_id) {
        ($media) = pkg('Media')->find(media_id => $media_id);
        croak("Unable to find media '$media_id'") unless $media;
    } else {
        $media = $self->get_session_media_obj($edit_uuid);
        croak("Unable to load media from sesssion for edit_uuid '$edit_uuid'") unless $media;
    }

    my $publisher = pkg('Publisher')->new();
    my $url;
    eval { $url = $publisher->preview_media(media => $media); };
    if (my $e = $@) {

        # load the error screen template, one way or another we'll
        # need it.
        my $template = $self->load_tmpl('media_error.tmpl');
        my @error_loop;

        if (ref $e and $e->isa('Krang::Publisher::FileWriteError')) {
            add_alert('file_write_error', path => $e->destination);

            # put the messages on the screen
            foreach my $err (get_alerts()) {
                push(@error_loop, {err => $err});
            }
            clear_alerts();

            # pass a more informative message to the log file - ops should know.
            my $err_msg = sprintf("Could not write '%s' to disk.  Error='%s'",
                $e->destination, $e->message);
            critical($err_msg);

        } else {
            croak($e);
        }

        # finish the error screen
        $template->param(error_loop => \@error_loop);
        return $template->output;
    }

    if ($no_view) {

        # add a message
        add_message(
            'media_preview',
            media_id => $media_id,
            url      => $media->preview_url,
            version  => $media->version
        );

        # return to my workspace
        return $self->redirect_to_workspace;
    } else {

        # redirect to preview
        my $scheme = PreviewSSL ? 'https' : 'http';
        $self->header_props(-uri => $scheme . '://' . $url);
        $self->header_type('redirect');
        return "Redirect: <a href=\"$url\">$url</a>";
    }
}

#
# given a list of stories, build the @stories and @media lists
# for assets linked to by these stories.
#
sub _build_asset_list {
    my $self = shift;
    my ($story_list, $media_list) = @_;

    my $user_id = $ENV{REMOTE_USER};

    my $publish_list = [];
    my @stories      = ();
    my @media        = ();

    my $publisher = pkg('Publisher')->new();

    # retrieve all stories linked to the submitted list.
    push(@{$publish_list}, @{$publisher->asset_list(story => $story_list, mode => 'publish')})
      if $story_list and @$story_list;

    # add previously submitted media objects to the list.
    push(@{$publish_list}, @$media_list)
      if $media_list and @$media_list;

    my $checked_out_assets = 0;

    # iterate over asset list to create display list.
    foreach my $asset (@$publish_list) {
        my $checked_out = 0;
        my $status      = '';

        # deal w/ checked out assets - a problem if assets are checked
        # out by a user other than the current user.
        if ($asset->checked_out) {
            my $checked_out_by = $asset->checked_out_by();
            if ($user_id != $checked_out_by) {
                $checked_out = 1;
                $status =
                  localize('Checked out by') . ' <b>'
                  . (pkg('User')->find(user_id => $asset->checked_out_by))[0]->login . '</b>';
            }
        }
        $checked_out_assets = $checked_out if $checked_out;

        if ($asset->isa('Krang::Story')) {
            push @stories,
              {
                id  => $asset->story_id,
                url => format_url(
                    url    => $asset->url,
                    class  => 'story-preview-link',
                    name   => 'story_' . $asset->story_id,
                    length => 20
                ),
                title       => $asset->title,
                checked_out => $checked_out,
                status      => $status
              };
        } elsif ($asset->isa('Krang::Media')) {
            push @media,
              {
                id  => $asset->media_id,
                url => format_url(
                    url    => $asset->url,
                    class  => 'media-preview-link',
                    name   => 'media_' . $asset->media_id,
                    length => 20
                ),
                title       => $asset->title,
                thumbnail   => $asset->thumbnail_path(relative => 1) || '',
                checked_out => $checked_out,
                status      => $status
              };

        } else {

            # Nothing else should make it this far.
            croak
              sprintf("%s: I have no idea what to do with this: ISA='%s'", __PACKAGE__, $_->isa());
        }
    }

    # add the even flag to stories and media
    my $even = 0;
    foreach my $asset (@stories, @media) {
        $asset->{even} = $even;
        $even = !$even;
    }

    return (\@stories, \@media, $checked_out_assets);

}

#
# _publish_assets_now($story_list_ref, $media_list_ref);
#
# Given lists of story & media objects, start the publish process on both.
# If errors occur, make entries in the message system & return.
#
sub _publish_assets_now {
    my $self = shift;
    my ($story_list, $media_list) = @_;
    my $query = $self->query;

    # this is a no-parse header script
    $self->header_type('none');
    print $query->header;

    # output the progress header
    my $template = $self->load_tmpl('progress.tmpl');
    my $charset = Charset || '';
    $template->param(charset => $charset);
    $|++;
    print $template->output;

    # start caching and setup an eval{} to catch death
    pkg('Cache')->start();
    eval {

        # run things to the publisher
        my $publisher = pkg('Publisher')->new();
        if (@$story_list) {
            # publish (without locking the session)
            pkg('Session')->unlock();
            eval {
                $publisher->publish_story(
                    story    => $story_list,
                    callback => \&_progress_callback
                );
            };
            pkg('Session')->load();

            if (my $err = $@) {
                # if there is an error, figure out what it is, create the
                # appropriate message and return.
                if (ref $err
                    && $err->isa('Krang::ElementClass::TemplateNotFound'))
                {
                    if ($err->included_file) {
                        add_alert(
                            'missing_template_include',
                            filename      => $err->template_name,
                            included_file => $err->included_file,
                            category_url  => $err->category_url
                        );
                        critical(
                            sprintf(
                                "Unable to find included_file '%s' in template '%s' for Category '%s'",
                                $err->included_file, $err->template_name, $err->category_url
                            )
                        );
                    } else {
                        add_alert(
                            'missing_template',
                            filename     => $err->template_name,
                            category_url => $err->category_url
                        );
                        critical(
                            sprintf(
                                "Unable to find template '%s' for Category '%s'",
                                $err->template_name, $err->category_url
                            )
                        );
                    }
                } elsif (ref $err
                    && $err->isa('Krang::ElementClass::TemplateParseError'))
                {
                    add_alert(
                        'template_parse_error',
                        element_name  => $err->element_name,
                        template_name => $err->template_name,
                        category_url  => $err->category_url,
                        error_msg     => $err->message
                    );
                    critical($err->error_msg);
                } elsif (ref $err
                    && $err->isa('Krang::Publisher::FileWriteError'))
                {

                    add_alert('file_write_error', path => $err->destination);

                    # pass a more informative message to the log file - ops should know.
                    my $err_msg = sprintf("Could not write '%s' to disk.  Error='%s'",
                        $err->destination, $err->message);
                    critical($err_msg);
                } elsif (ref $err
                    && $err->isa('Krang::Publisher::ZeroSizeOutput'))
                {
                    add_alert(
                        'zero_size_output',
                        story_id     => $err->story_id,
                        category_url => $err->category_url,
                        story_class  => $err->story_class
                    );
                    critical($err->message);
                } else {
                    add_alert('unknown_publish_error');
                    $err = "Error while publishing: $err";
                    critical($err); # to krang.log
                    warn "$err\n";  # to apache log
                }

                # make sure to turn off caching
                pkg('Cache')->stop();
                debug("Cache Stats " . join(' : ', pkg('Cache')->stats()));

                return;

            } else {

                # otherwise, we're good.
                foreach my $story (@$story_list) {

                    # add a publish message for the UI
                    add_message(
                        'story_publish',
                        story_id => $story->story_id,
                        url      => $story->url,
                        version  => $story->version
                    );
                }
            }
        }

        if (@$media_list) {
            # publish (without locking the session)
            pkg('Session')->unlock();
            $publisher->publish_media(media => $media_list);
            pkg('Session')->load();

            foreach my $media (@$media_list) {

                # add a publish message for the UI
                add_message(
                    'media_publish',
                    media_id => $media->media_id,
                    url      => $media->url,
                    version  => $media->version
                );
            }
        }
    };
    my $err = $@;

    # done caching
    pkg('Cache')->stop();
    debug("Cache stats " . join(' : ', pkg('Cache')->stats()));

    # die if you want to
    croak($err) if $err;

    # dynamic redirect to workspace, but give the page time to update
    # itself
    print qq|
    <script type="text/javascript">
        setTimeout(function() { location.replace('workspace.pl') }, 10)
    </script>|;

    return;
}

#
# _schedule_assets($story_listref, $media_listref, $date);
#
# Takes lists of story & media objects and makes entries for them in the scheduler.
#

sub _schedule_assets {

    my $self = shift;
    my ($story_list, $media_list, $date) = @_;

    foreach my $story (@$story_list) {
        my $sched = pkg('Schedule')->new(
            object_type => 'story',
            object_id   => $story->story_id,
            action      => 'publish',
            repeat      => 'never',
            date        => $date
        );
        $sched->save();
        add_message(
            'story_schedule',
            story_id         => $story->story_id,
            version          => $story->version,
            publish_datetime => $date->cdate()
        );

        # check scheduled story back in.
        $story->checkin();

    }
    foreach my $media (@$media_list) {
        my $sched = pkg('Schedule')->new(
            object_type => 'media',
            object_id   => $media->media_id,
            action      => 'publish',
            repeat      => 'never',
            date        => $date
        );
        $sched->save();
        add_message(
            'media_schedule',
            media_id         => $media->media_id,
            version          => $media->version,
            publish_datetime => $date->cdate()
        );
        $media->checkin();
    }

    return;

}

1;

=back

=cut

