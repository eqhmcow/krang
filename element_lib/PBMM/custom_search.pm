package PBMM::custom_search;
use strict;
use warnings;

=head1 NAME

PBMM::custom_search

=head1 DESCRIPTION

PBMM custoM_search element class for Krang. 

=cut


use base 'Krang::ElementClass';
use Krang::List;
use Krang::ListItem;

sub new {
   my $pkg = shift;
   my %args = ( name => 'custom_search',
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

    foreach my $list_name qw( Topics Geographies Sources ) {
        my @list_items = Krang::ListItem->find( list_id => (Krang::List->find( name => $list_name ))[0]->list_id );
        my @list_item_loop;
        foreach my $li (@list_items) {
            push(@list_item_loop, { list_item_id => $li->list_item_id, data => $li->data }); 
        }

        $tmpl->param( lc($list_name).'_loop' => [@list_item_loop] );
    }

    $self->SUPER::fill_template( %args );
}

1;
