package PBMM::table_of_contents;
use strict;
use warnings;

=head1 NAME

PBMM::table_of_contents

=head1 DESCRIPTION

PBMM table_of_contents element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'table_of_contents',
                children => 
                [
                    Krang::ElementClass::CheckBox->new(name => 'table_background',
                                                       min => 1,
                                                        max => 1,
                                                        allow_delete => 1,
                                                        reorderable => 0,
                                                        default => 0
                                                     ),
                     Krang::ElementClass::Text->new(name         => "table_title",
                                                    min => 1,
                                                        max => 1,
                                                        allow_delete => 1,
                                                        reorderable => 0 ), 
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;
                                                                                
    my $tmpl      = $args{tmpl};
    my $cat   = $args{element}->object;
    my $story   = $args{publisher}->story;
    my $publisher = $args{publisher};

    # if this is an issue cover, dont show it on side
    return if ($story->class->name eq 'issue_cover');
   
     
    my $issue_id = $story->element->child('issue_id') || '';
    return if not $issue_id;
    $issue_id = $issue_id->data;

    return if (not $issue_id);
    
    my ($issue_cover) = Krang::Story->find( class => 'issue_cover', element_index => [ issue_id => $issue_id ]);

    return if (not $issue_cover);

    my $element = $issue_cover->element;
    my @element_children = $element->children();
    my @element_loop;

    foreach my $child (@element_children) {
        my $name     = $child->name;
        if ($name eq 'lead_in') {
            my $s = $child->child('story')->data;
            my $ptitle = $s->element->child('promo_title')->data || $story->title;
            my $pteaser = $s->element->child('promo_teaser')->data || '';
            my $url = $child->child('story')->template_data(publisher => $publisher);
            push(@element_loop, { title => $ptitle, teaser => $pteaser, url => $url, is_lead_in => 1 });
        } elsif ($name eq 'large_header') {
            push(@element_loop, { large_header => $child->publish( publisher => $publisher), "is_large_header" => 1 });    
        }
    }

    $tmpl->param( element_loop => \@element_loop ) if @element_loop;
}

1;
