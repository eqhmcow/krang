package PBMM::category_archive;
use strict;
use warnings;
use PBMM::meta;
use PBMM::promo;

use base 'Krang::ElementClass::TopLevel';

use PBMM::ocs_hooks qw(_publish delete_hook);

# wrap ocs_hooks::_publish since SUPER doesn't work in exported methods
sub publish {
    my $self = shift;
    
    return $self->_publish(@_) . $self->SUPER::publish(@_);
}

sub new {
   my $pkg = shift;
   my @fixed = (min  => 1,
                 max  => 1,
                 reorderable => 0,
                 allow_delete => 0);

   my %args = ( name => 'category_archive',
                children =>
                [
                PBMM::story_ocs->new(),
                Krang::ElementClass::CheckBox->new(name => 'enhanced_content',
                                           @fixed),
                Krang::ElementClass::CheckBox->new(name => 'automatic_leadins',
                                                    default => 1,
                                           @fixed),
                Krang::ElementClass::Text->new( name => 'leadins_per_page',
                                                default => 25,
                                       @fixed),
                Krang::ElementClass::CheckBox->new(    name => 'link_to_top_of_page',
                                            default => 1,
                                            min => 1,
                                            max => 1,
                                            allow_delete => 0,
                                            reorderable => 0 ),
                PBMM::meta->new(),
                PBMM::promo->new(),
                PBMM::custom_search->new(max => 1),
                Krang::ElementClass::Text->new(name => "large_header"),
                Krang::ElementClass::Text->new(name => "small_header"),
                Krang::ElementClass::Textarea->new(name => "paragraph",
                                                    bulk_edit => 1),
                PBMM::image->new(),
                PBMM::lead_in->new(), 
                PBMM::table_of_contents->new(),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;
                                                                                    my $tmpl      = $args{tmpl};
    my $story   = $args{element}->object;
    my $publisher = $args{publisher};

    # get stories in this category
    my @s = Krang::Story->find( category_id => $story->category->category_id, published => '1', order_by => 'cover_date', order_desc => 1 );

    my @story_loop;
    my @page_loop;
    my $story_count = 0;

    my $page_count;
    my @pnums;

    foreach my $s (@s) {
        next if ($s->story_id eq $story->story_id);

        my $ptitle = $s->element->child('promo_title')->data || $s->title;
        my $pteaser = $s->element->child('promo_teaser')->data || '';
        my $image = $s->element->child('promo_image_small') || '';
        my $promo_image_width = $image->data->width if $image;
        my $promo_image_height = $image->data->height if $image;
        $image = $image->template_data(publisher => $publisher) if $image;
        my $byline = $s->element->child('byline') ? $s->element->child('byline')->data : '';
        my $source = $s->element->child('source') ? $s->element->child('source')->data : '';
        my $enhanced_content = $s->element->child('enhanced_content') ? $s->element->child('enhanced_content')->data : '';

           my %contrib_types = Krang::Pref->get('contrib_type');
                                                                           
                                                                           
        my %contribs = ();
        my @contributors  = ();
        my @contrib_order = ();
                                                                           
        # get the contributors for the story.
        foreach my $contrib ($s->contribs()) {
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
            push @{$contribs{$cid}{contrib_type_loop}}, {contrib_type_id => $contrib_type_id,
                                                     contrib_type_name => $contrib_types{$contrib_type_id}};
                                                                           
                                                                           
        }
                                                                           
                                                                           
        foreach my $contrib_id (@contrib_order) {
            push @contributors, $contribs{$contrib_id};
        }

        push (@story_loop, {page_story_count => ++$story_count, url => 'http://'.($publisher->is_preview ? $s->preview_url : $s->url).'/', 
                            promo_teaser => $pteaser,
                            promo_title => $ptitle,
                            promo_image => $image,
                            promo_image_width => $promo_image_width,
                            promo_image_height => $promo_image_height,
                            byline => $byline,
                            source => $source,
                            enhanced_content => $enhanced_content,
                            contrib_loop => [@contributors],
                            cover_date => $s->cover_date->strftime('%b %e, %Y') } ); 

        if ($story_count == $args{element}->child('leadins_per_page')->data) {
            push (@page_loop, { page_count => ++$page_count, story_loop => [@story_loop] } );
            @story_loop = ();
            $story_count = 0;
            push (@pnums, {page_number => $page_count } );
        }
    } 

    if ($story_count) {
        push (@page_loop, { page_count => ++$page_count, story_loop => [@story_loop] } );
        push (@pnums, {page_number => ($page_count-1) ? ($page_count-1) : ''} );
    }
        
    if ($page_count > 1) {
        # finish the pnum_loop
        $tmpl->param(pnum_loop => \@pnums);
    } else {
        @pnums = ();
        $tmpl->param(pnum_loop => \@pnums);
    }


    $tmpl->param( page_loop => \@page_loop );

    $self->SUPER::fill_template( %args );
}
1;
