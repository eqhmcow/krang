package Default::lead_in;
use strict;
use warnings;
use base 'Krang::ElementClass';

=head1 NAME

Default::lead_in

=head1 DESCRIPTION

Default lead-in element class for Krang. This element uses
Krang::ElementClass as a base.

=cut

use Carp qw(croak);

sub new {
   my $pkg = shift;
   my %args = ( name => 'lead_in', 
                children =>
                [
                 Krang::ElementClass::StoryLink->new( name => 'story',
                                                    min => 1,
                                                    max => 1,
                                                    allow_delete => '0',
                                                    reorderable => '0',
                                                    required => 1 ),    
                 Krang::ElementClass::PopupMenu->new(name => "type",
                                                    reorderable => '0',
                                                   min => 1,
                                                   max => 1,
                                                   allow_delete => '0',
                                                   values => [ "Large",
                                                               "Small"],
                                                   default => "Small"
                                                           ),
                 Krang::ElementClass::PopupMenu->new(name => "image_alignment",
                                                    reorderable => '0',
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

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($header, $data);
    if ($header = $element->child('story') and
        $data   = "<br><b>Title:</b> ".$header->data->title."<br><b>URL:</b> ".$header->data->url ) {
        return $data;
    }
    return '';
}

sub fill_template {
    my ($self, %args) = @_;

    my $tmpl      = $args{tmpl};
    my $story   = $args{element}->child('story')->data;
    my $publisher = $args{publisher};

    return if not $story;

    my $ptitle = $story->element->child('promo_title')->data || $story->title;
    $tmpl->param( promo_title => $ptitle );

    my $pteaser = $story->element->child('promo_teaser')->data || '';
    $tmpl->param( promo_teaser => $pteaser ) if $pteaser;

    my $type = lc($args{element}->child('type')->data);

    my $image = $story->element->child('promo_image_'.$type) || '';
    $image = $image->template_data(publisher => $publisher) if $image; 
    $tmpl->param( promo_image => $image) if $image;

    $tmpl->param( url => $args{element}->child('story')->template_data(publisher => $publisher) );
   
    $tmpl->param( image_alignment => $args{element}->child('image_alignment')->data ); 
    $tmpl->param( type => $type );
}


1;
