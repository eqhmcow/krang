package Default::lead_in;
use strict;
use warnings;
use base 'Krang::ElementClass::StoryLink';

=head1 NAME

Default::lead_in

=head1 DESCRIPTION

Default lead-in element class for Krang. This element uses
Krang::ElementClass::StoryLink as a base.

=cut

use Carp qw(croak);

sub new {
   my $pkg = shift;
   my %args = ( name => 'lead_in', 
                children =>
                [
                 Krang::ElementClass::PopupMenu->new(name => "type",
                                                   min => 1,
                                                   max => 1,
                                                   allow_delete => '0',
                                                   values => [ "Large",
                                                               "Small"],
                                                   default => "Small"
                                                           ),
                 Krang::ElementClass::PopupMenu->new(name => "alignment",

                                                     min => 1,
                                                     max => 1,
                                                     allow_delete => '0',
                                                     values => [ "Left",
                                                                 "Right"],
                                                     default => "Left")
                ],
                @_);


   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;

    my $tmpl      = $args{tmpl};
    my $story   = $args{element}->data;
    my $publisher = $args{publisher};

    my $ptitle = $story->element->child('promo_title')->data || $story->title;
    $tmpl->param( promo_title => $ptitle );

    my $pteaser = $story->element->child('promo_teaser')->data || '';
    $tmpl->param( promo_teaser => $pteaser ) if $pteaser;

    my $image = $story->element->child('promo_image_small')->child('media')->template_data(publisher => $publisher) || '';
    $tmpl->param( promo_image => $image) if $image;

    $tmpl->param( url => $args{element}->template_data(publisher => $publisher) );
}


1;
