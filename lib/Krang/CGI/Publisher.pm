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
                         publish_assets
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

    my ($story) = Krang::Story->find(story_id => $story_id);

    my $t = $self->load_tmpl('publish_list.tmpl',
                             associate => $query,
                             loop_context_vars => 1,
                             die_on_bad_params => 0
                            );

    my $publisher = Krang::Publisher->new();
    my $publish_list = $publisher->get_publish_list(story => $story);

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

    $t->param(stories => \@stories, media => \@media);

    # add date chooser
    $t->param(publish_date_chooser => datetime_chooser(name => 'publish_date',
                                                       query => $query));

    return $t->output();

}


=item publish_assets

Starts the publish process for a given story specified by the CGI parameter 'story_id'.

Requires the following parameters: story_id, publish_now, publish_date_xxx (if publish_now == 0)

If publish_now == 1, start publish & redirect to workspace.

If putlist_now == 0, schedule publish & redirect to workspace.

=cut

sub publish_assets {
    my $self = shift;
    my $query = $self->query;

    my $story_id = $query->param('story_id');
    croak("Missing required story_id parameter") unless $story_id;
    my $publish_now = $query->param('publish_now');

    my ($story) = Krang::Story->find(story_id => $story_id);

    if ($publish_now) {
        # run things to the publisher
        my $publisher = Krang::Publisher->new();
        $publisher->publish_story(story => $story);
        # add a message
        add_message('story_publish', story_id => $story_id,
                    url => $story->url,
                    version => $story->version);
    } else {
        # pass things to the scheduler
        my $date = decode_datetime(name => 'publish_date', query => $query);
        my $sched = Krang::Schedule->new(object_type => 'story',
                                         object_id   => $story_id,
                                         action      => 'publish',
                                         repeat      => 'never',
                                         date        => $date);
        $sched->save();
        add_message('story_schedule',
                    story_id => $story_id,
                    version => $story->version,
                    publish_datetime => $date->cdate()
                   );

    }

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

1;

=back

=cut

