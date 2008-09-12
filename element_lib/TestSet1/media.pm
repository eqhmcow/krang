package TestSet1::media;

=head1 NAME

  TestSet1::media;

=head1 DESCRIPTION

Media element class for Krang.

=cut

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'ElementClass::Media';

sub new {
    my $pkg = shift;
    my %args = (
      name => 'media',
      children => [ pkg('ElementClass::Text')->new(name => 'sample_text'),
                    'page',
                  ],
      ,
    );
    return $pkg->SUPER::new(%args);
}

1;
