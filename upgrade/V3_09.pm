package V3_09;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader Conf => qw(KrangRoot InstanceElementSet);
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'ElementLibrary';
use File::Spec::Functions qw(catfile);
use Cwd qw(cwd);

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();
    $dbh->do('ALTER TABLE template ADD COLUMN read_only BOOL NOT NULL DEFAULT 0');
    $dbh->do('ALTER TABLE media ADD COLUMN read_only BOOL NOT NULL DEFAULT 0');
}

sub per_installation {
    # nothing yet
}

1;
