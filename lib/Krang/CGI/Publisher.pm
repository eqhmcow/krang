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
use Carp qw(croak);

use base 'Krang::CGI';

sub setup {
    my $self = shift;
    $self->start_mode('preview_story');
    $self->mode_param('rm');
    $self->tmpl_path('Publisher/');
    $self->run_modes([qw(
        preview_story
    )]);

}

=item preview_story

Publishes a story to preview and returns a redirect to the resulting
page on the preview story.  Requires a story_id parameter with the ID
for the story to be previewed.

=cut

sub preview_story {
    my $self = shift;
    my $query = $self->query;

    my $story_id = $query->param('story_id');
    croak("Missing required story_id parameter.") unless $story_id;
    
    my ($story) = Krang::Story->find(story_id => $story_id);
    croak("Unable to find story '$story_id'")     unless $story;

    my $publisher = Krang::Publisher->new();
    my $url = $publisher->preview_story(story => $story);

    # this should always be true
    assert($url eq $story->preview_url) if ASSERT;

    # redirect to preview
    $self->header_type('redirect');
    $self->header_props(-url=>"http://$url");
    return "Redirecting to <a href='http://$url'>http://$url</a>.";
}

1;

=back

=cut

