package PBMM::article;
use base 'PBMM::top';

sub new {
    my $pkg = shift;
    my %args = ( name => 'article',
                 children => [
                              'page'
                             ]);
    return $pkg->SUPER::new(%args);
}

1;
