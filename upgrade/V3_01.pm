package V3_01;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

# Add new krang.conf directive PreviewSSL
sub per_installation {

}

sub per_instance {
    my $self = shift;
    my $dbh = dbh();

    # remove deprecated 'priority' field from story table
    $dbh->do('ALTER TABLE story DROP COLUMN priority');
}

1;
