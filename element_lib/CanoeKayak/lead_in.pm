package CanoeKayak::lead_in;
use strict;
use warnings;
use base 'Krang::ElementClass';

use Krang::Log 'info';

sub new {
    my $pkg  = shift;
    my %args =
      (name      => 'lead_in',
       children  => [
                     Krang::ElementClass::StoryLink->new(name => 'story',
                                                         min => 1,
                                                         max => 1,
                                                         allow_delete => 0,
                                                         reorderable => 0),

                     Krang::ElementClass::PopupMenu->new(name => 'type',
                                                         display_name =>
                                                         'Promo Type',
                                                         min => 1,
                                                         max => 1,
                                                         allow_delete => 0,
                                                         default => 'small',
                                                         values  =>
                                                         ['small',
                                                          'large',
                                                          'no image'],
                                                         labels =>
                                                         {'no image' =>
                                                          'no image',
                                                          'large' => 'large',
                                                          'small' => 'small'},
                                                        )
                    ],
       @_);
    return $pkg->SUPER::new(%args);
}


sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($header, $data);
    $header = $element->child('story');

    if ($header->data) {
        $data = "<br><b>Title:</b> ". $header->data->title .
          "<br><b>URL:</b> " . $header->data->url;
        return $data;
    }

    return '';
}


sub fill_template {
    my ($self, %args) = @_;

    my $tmpl = $args{tmpl};
    my $story = $args{element}->child('story')->data;
    my $publisher = $args{publisher};
    my $element = $args{element};

    return if not $story;

    my $ptitle = $story->element->child('promo_title')->data || $story->title;
    $tmpl->param(promo_title => $ptitle);
    $tmpl->param(promo_teaser => $story->element->child('promo_teaser')->data);

    # set cover date
    $tmpl->param(cover_date =>
                 $story->cover_date->strftime('%b %e, %Y %l:%M %p'));

    $tmpl->param(link => $story->title);
    $tmpl->param(url => $story->url);

    my $type = $args{element}->child('type')->data;

    if ($type ne 'no_image') {
        my $promo = $story->element->child('promo_image_'.$type) || '';

        if ($promo) {
            my $src = "http://" . $promo->child('media')->data->url;
            $tmpl->param(promo_image => $src);
        }
    }

    $tmpl->param(type => $type);

    $tmpl->param(byline => $story->element->child('byline')->data)
      if $story->element->child('byline');
    $tmpl->param(source => $story->element->child('source')->data)
      if $story->element->child('source');

    my %contrib_types = Krang::Pref->get('contrib_type');
    my %contribs = ();
    my @contributors  = ();
    my @contrib_order = ();

    # get the contributors for the story.
    foreach my $contrib ($story->contribs()) {
        my $cid = $contrib->contrib_id();

        # check to see if this contributor exists - if so, save
        # on querying for information you already know.
        unless (exists($contribs{$cid})) {
            # preserve the order in which the contributors arrive.
            push @contrib_order, $cid;
            $contribs{$cid}{contrib_id} = $cid;
            $contribs{$cid}{prefix}     = $contrib->prefix();
            $contribs{$cid}{first}      = $contrib->first();
            $contribs{$cid}{middle}     = $contrib->middle();
            $contribs{$cid}{last}       = $contrib->last();
            $contribs{$cid}{suffix}     = $contrib->suffix();
            $contribs{$cid}{email}      = $contrib->email();
            $contribs{$cid}{phone}      = $contrib->phone();
            $contribs{$cid}{bio}        = $contrib->bio();
            $contribs{$cid}{url}        = $contrib->url();
            $contribs{$cid}{full_name}  = $contrib->full_name();

            my $media = $contrib->image();
            if (defined($media)) {
                if ($publisher->is_preview) {
                    $contribs{$cid}{image_url} = $media->preview_url();
                } elsif ($publisher->is_publish) {
                    $contribs{$cid}{image_url} = $media->url();
                }
            }
        }

        # add the selected contributor type to the contrib_type_loop
        my $contrib_type_id = $contrib->selected_contrib_type();
        push @{$contribs{$cid}{contrib_type_loop}},
          {contrib_type_id => $contrib_type_id,
           contrib_type_name => $contrib_types{$contrib_type_id}};
    }

    foreach my $contrib_id (@contrib_order) {
        push @contributors, $contribs{$contrib_id};
    }

    $tmpl->param( contrib_loop => \@contributors );
}


1;
