package PBMM::article;
use strict;
use warnings;
use base 'Krang::ElementClass::TopLevel';
use PBMM::meta;

sub new {
    my $pkg = shift;
    my %args = ( name => 'article',
                 children => [
                              PBMM::meta->new(),
                              'page'

                             ]);
    return $pkg->SUPER::new(%args);
}

1;
