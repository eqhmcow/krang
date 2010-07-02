package V3_11;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB   => 'dbh';
use File::Spec::Functions qw(catfile);

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();
    $dbh->do('UPDATE story_category SET url = TRIM(TRAILING "/" FROM url)');
}

sub per_installation {
    # nothing yet
}

1;
