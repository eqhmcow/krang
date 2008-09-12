package Default::media;

=head1 NAME

  Default::media;

=head1 DESCRIPTION

Media element class for Krang.

=cut

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'ElementClass::Media';

sub new {
    my $pkg = shift;
    my %args = (
      name => 'media',
      children => [],
      ,
    );
    return $pkg->SUPER::new(%args);
}

1;
