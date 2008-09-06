package V3_04;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

sub per_installation {
}

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();

    # add the 'language' preference
    $dbh->do('INSERT INTO pref (id, value) VALUES ("language", "en")');
}

1;
