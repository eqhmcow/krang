package Krang::CGI::Publisher;
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

use Krang::Session qw(%session);
use Krang::Publisher;
use Krang::Story;
use Krang::Log qw(debug assert ASSERT);
use Krang::Widget qw(format_url datetime_chooser decode_datetime);
use Krang::Message qw(add_message);
use Time::Piece;

use Carp qw(croak);

use base 'Krang::CGI';

sub setup {
    my $self = shift;
    $self->start_mode('preview_story');
    $self->mode_param('rm');
    $self->tmpl_path('Publisher/');
    $self->run_modes([qw(
                         preview_story
                         preview_media
                         publish_story
                         publish_story_list
                         publish_assets
                         publish_media
    )]);

}


=item publish_story

Presents a list of story and media objects to be published.  Allows
the user to schedule a publish date.

Requires story_id parameter with the ID of the story to be published.

=cut

sub publish_story {
    my $self = shift;
    my $query = $self->query;

    my $story_id = $query->param('story_id');
    croak("Missing required story_id parameter") unless $story_id;

    $query->delete('story_id');

    my ($story) = Krang::Story->find(story_id => $story_id);

    my $t = $self->load_tmpl('publish_list.tmpl',
                             associate => $query,
                             loop_context_vars => 1,
                             die_on_bad_params => 0
                            );

    my ($stories, $media) = $self->_build_asset_list([$story]);

    $t->param(stories => $stories, media => $media);
    $t->param(asset_id_list => [{id => "story_$story_id"}]);

    # add date chooser
    $t->param(publish_date_chooser => datetime_chooser(name => 'publish_date',
                                                       query => $query));

    return $t->output();

}


=item publish_story_list

Presents a list of story and media objects to be published.  Allows
the user to schedule a publish date.

Requires story_id_list parameter with the IDs of the story to be published.

=cut

sub publish_story_list {
    my $self = shift;
    my $query = $self->query;

    my (@story_list,@media_list,@story_id_list,@media_id_list);

    my @asset_id_list = $query->param('krang_pager_rows_checked');
    $query->delete('krang_pager_rows_checked');

    my $t = $self->load_tmpl('publish_list.tmpl',
                             associate => $query,
                             loop_context_vars => 1,
                             die_on_bad_params => 0
                            );
    my @id_list;

    foreach (@asset_id_list) {
        $_ =~ /(\w+)_(\d+)/;
        ($1 eq 'story') ? ( push @story_id_list, $2 ) :
          ($1 eq 'media') ? ( push @media_id_list, $2 ) : 
            croak __PACKAGE__ . ": what to do with asset = '$1'??";
        push @id_list, { id => $_ };
    }


    $t->param(asset_id_list => \@id_list);

    @story_list = Krang::Story->find(story_id => \@story_id_list) if @story_id_list;
    @media_list = Krang::Media->find(media_id => \@media_id_list) if @media_id_list;


    my ($stories, $media) = $self->_build_asset_list(\@story_list, \@media_list);

    $t->param(stories => $stories, media => $media);

    # add date chooser
    $t->param(publish_date_chooser => datetime_chooser(name => 'publish_date',
                                                       query => $query));

    return $t->output();

}


=item publish_assets

Starts the publish process for a given set of stories stories specified by the CGI parameter 'asset_publish_list'.

Requires the following parameters: story_ids, publish_now, publish_date_xxx (if publish_now == 0)

If publish_now == 1, start publish & redirect to workspace.

If putlist_now == 0, schedule publish & redirect to workspace.

=cut

sub publish_assets {
    my $self = shift;
    my $query = $self->query;

    my @asset_id_list = ( $query->param('asset_id_list') );
    croak("Missing required asset_id_list parameter") unless @asset_id_list;
    my $publish_now = $query->param('publish_now');

    my @story_id_list;
    my @media_id_list;

    my @story_list;
    my @media_list;

    foreach (@asset_id_list) {
        $_ =~ /(\w+)_(\d+)/;
        ($1 eq 'story') ? ( push @story_id_list, $2 ) :
          ($1 eq 'media') ? ( push @media_id_list, $2 ) : 
            croak __PACKAGE__ . ": what to do with asset = '$1'??";
    }

    @story_list = Krang::Story->find(story_id => \@story_id_list) if @story_id_list;
    @media_list = Krang::Media->find(media_id => \@media_id_list) if @media_id_list;

    if ($publish_now) {
        # run things to the publisher
        my $publisher = Krang::Publisher->new();
        if (@story_list) {
            $publisher->publish_story(story => \@story_list);
            foreach my $story (@story_list) {
                # add a message
                add_message('story_publish', story_id => $story->story_id,
                            url => $story->url,
                            version => $story->version);
            }
        }
        if (@media_list) {
            $publisher->publish_media(media => \@media_list);
            foreach my $media (@media_list) {
                # add a message
                add_message('media_publish', media_id => $media->media_id,
                            url => $media->url,
                            version => $media->version);
            }
        }
    } else {
        # pass things to the scheduler
        my $date = decode_datetime(name => 'publish_date', query => $query);
        foreach my $story (@story_list) {
            my $sched = Krang::Schedule->new(object_type => 'story',
                                             object_id   => $story->story_id,
                                             action      => 'publish',
                                             repeat      => 'never',
                                             date        => $date);
            $sched->save();
            add_message('story_schedule',
                        story_id => $story->story_id,
                        version => $story->version,
                        publish_datetime => $date->cdate()
                       );
        }
        foreach my $media (@media_list) {
            my $sched = Krang::Schedule->new(object_type => 'media',
                                             object_id   => $media->media_id,
                                             action      => 'publish',
                                             repeat      => 'never',
                                             date        => $date);
            $sched->save();
            add_message('media_schedule',
                        media_id => $media->media_id,
                        version => $media->version,
                        publish_datetime => $date->cdate()
                       );
        }


    }

    # return to my workspace
    $self->header_props(-uri => 'workspace.pl');
    $self->header_type('redirect');
    return "";

}


=item publish_media

Publishes a media object immediately.  No scheduling done here.

requires media_id

returns the user to 'My Workspace' when done.

=cut

sub publish_media {
    my $self = shift;
    my $query = $self->query;

    my $media_id = $query->param('media_id');
    croak("Missing required media_id parameter") unless $media_id;

    my ($media) = Krang::Media->find(media_id => $media_id);

    # run things to the publisher
    my $publisher = Krang::Publisher->new();
    $publisher->publish_media(media => $media);
    # add a message
    add_message('media_publish', media_id => $media_id,
                url => $media->url,
                version => $media->version);

    # return to my workspace
    $self->header_props(-uri => 'workspace.pl');
    $self->header_type('redirect');
    return "";

}



=item preview_story

Publishes a story to preview and returns a redirect to the resulting
page on the preview story.  Requires a story_id parameter with the ID
for the story to be previewed or a session parameter set to the
session key containing the story to preview.

=cut

sub preview_story {
    my $self = shift;
    my $query = $self->query;

    my $session_key = $query->param('session');
    my $story_id    = $query->param('story_id');
    croak("Missing required story_id or session parameter.")
      unless $story_id or $session_key;

    my $story;
    unless ($session_key) {
        ($story) = Krang::Story->find(story_id => $story_id);
        croak("Unable to find story '$story_id'")
          unless $story;
    } else {
        $story = $session{$session_key};
        croak("Unable to load story from sesssion '$session_key'")
          unless $story;
    }

    my $publisher = Krang::Publisher->new();
    my $url = $publisher->preview_story(story => $story);

    # this should always be true
    assert($url eq $story->preview_url) if ASSERT;

    # redirect to preview
    $self->header_type('redirect');
    $self->header_props(-url=>"http://$url");
    return "Redirecting to <a href='http://$url'>http://$url</a>.";
}

=item preview_media

Publishes a media object to preview and returns a redirect to the
resulting URL.  Requires a media_id parameter with the ID for the
media to be previewed, or a parameter called session set to the
session key containing the media object.

=cut

sub preview_media {
    my $self = shift;
    my $query = $self->query;

    my $session_key = $query->param('session');
    my $media_id    = $query->param('media_id');
    croak("Missing required media_id or session parameter.")
      unless $media_id or $session_key;

    my $media;
    unless ($session_key) {
        ($media) = Krang::Media->find(media_id => $media_id);
        croak("Unable to find media '$media_id'")
          unless $media;
    } else {
        $media = $session{$session_key};
        croak("Unable to load media from sesssion '$session_key'")
          unless $media;
    }

    my $publisher = Krang::Publisher->new();
    my $url = $publisher->preview_media(media => $media);

    # this should always be true
    assert($url eq $media->preview_url) if ASSERT;

    # redirect to preview
    $self->header_type('redirect');
    $self->header_props(-url=>"http://$url");
    return "Redirecting to <a href='http://$url'>http://$url</a>.";
}



#
# given a list of stories, build the @stories and @media lists
# for assets linked to by these stories.
#
sub _build_asset_list {
    my $self = shift;
    my ($story_list, $media_list) = @_;

    my $publisher = Krang::Publisher->new();
    my $publish_list = $publisher->get_publish_list(story => $story_list);

    # build @stories and @media.
    my @stories = ();
    my @media = ();

    foreach my $asset (@$publish_list) {
        if ($asset->isa('Krang::Story')) {
            push @stories, {id    => $asset->story_id,
                            url   => format_url(url    => $asset->url,
                                                linkto => "javascript:preview_story('" . $asset->story_id . "')",
                                                length => 40
                                               ),
                            title => $asset->title
                           };
        } elsif ($asset->isa('Krang::Media')) {
            push @media, {id        => $asset->media_id,
                          url       => format_url(url    => $asset->url,
                                                  linkto => "javascript:preview_media('" . $asset->media_id . "')",
                                                  length => 40
                                                 ),
                          title     => $asset->title,
                          thumbnail => $asset->thumbnail_path(relative => 1) || ''
                         };

        } else {
            croak sprintf("%s: I have no idea what to do with this: ISA='%s'", __PACKAGE__, $_->isa());
        }
    }

    return (\@stories, \@media);

}

1;

=back

=cut

