package Default::category;
use strict;
use warnings;

=head1 NAME

Default::category

=head1 DESCRIPTION

Default category element class for Krang.  It has no subelements at the
moment.

=cut


use base 'Krang::ElementClass::TopLevel';

sub new {
   my $pkg = shift;
   my %args = ( name => 'category',
                children => [
                             Krang::ElementClass::Text->new(name => 'display_name',
                                                            allow_delete => 0,
                                                            min => 1,
                                                            max => 1,
                                                            reorderable => 0,
                                                            required => 1),
                            ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;
    my $story   = $args{publisher}->story;
    my $tmpl      = $args{tmpl};
    $tmpl->param( metadata_title =>  $story->element->child_data('metadata_title'));
    $tmpl->param( metadata_description =>  $story->element->child_data('metadata_description') );
    my $keywords = $story->element->child_data('metadata_keywords') || [];
    my @keys;
    foreach my $kw (@$keywords) {
        push (@keys, {metadata_keyword => $kw});
    }
    $tmpl->param( metadata_keyword_loop => \@keys );
    $self->SUPER::fill_template( %args ); 
}

1;

   
